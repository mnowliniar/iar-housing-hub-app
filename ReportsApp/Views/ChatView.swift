//
//  ChatView.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/13/26.
//


import SwiftUI
import UIKit
import WebKit
import Charts

struct ChatView: View {
    @StateObject private var chat = ChatManager()
    @FocusState private var inputFocused: Bool
    @State private var activeGutsContent: GutsModalContent?

    private func associatedGutsText(for index: Int) -> String? {
        guard chat.messages.indices.contains(index) else { return nil }

        if chat.messages[index].payloadType == .guts {
            return chat.messages[index].text
        }

        for nextIndex in (index + 1)..<chat.messages.count {
            if chat.messages[nextIndex].payloadType == .guts {
                return chat.messages[nextIndex].text
            }
        }

        if index > 0 {
            for previousIndex in stride(from: index - 1, through: 0, by: -1) {
                if chat.messages[previousIndex].payloadType == .guts {
                    return chat.messages[previousIndex].text
                }
            }
        }

        return nil
    }

    private func isMessageExpanded(at index: Int) -> Bool {
        false
    }

    private func toggleGuts(at index: Int) {
        guard let gutsText = associatedGutsText(for: index) else { return }
        activeGutsContent = GutsModalContent(text: gutsText)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(chat.conversationName ?? "Chat")
                    .font(.headline)
                Spacer()
                Button("New") {
                    chat.newChat()
                }
            }
            .padding()

            Divider()

            if !chat.statusMessages.isEmpty {
                StatusPanel(messages: chat.statusMessages)
                    .padding(.horizontal)
                    .padding(.top, 10)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    //LazyVStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Ask a question")
                                    .font(.headline)
                                Text("Try asking about markets, trends, prices, inventory, or a specific geography.")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }

                        ForEach(Array(chat.messages.enumerated()), id: \.element.id) { index, message in
                            ChatBubble(
                                message: message,
                                isExpanded: isMessageExpanded(at: index),
                                onToggleGuts: {
                                    toggleGuts(at: index)
                                }
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
//                .onChange(of: chat.pendingScrollTarget) { _, target in
//                    guard let target else { return }
//
//                    Task { @MainActor in
//                        try? await Task.sleep(for: .milliseconds(300))
//                        withAnimation(.easeOut(duration: 0.2)) {
//                            proxy.scrollTo(target, anchor: .top)
//                        }
//                        chat.pendingScrollTarget = nil
//                    }
//                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask about the market…", text: $chat.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($inputFocused)

                Button {
                    let trimmed = chat.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }

                    inputFocused = false
                    Task { await chat.sendCurrentMessage() }
                } label: {
                    if chat.isSending {
                        ProgressView()
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                    }
                }
                .disabled(chat.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isSending)
            }
            .padding()
        }
        .navigationTitle("AI Chat")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeGutsContent) { item in
            NavigationStack {
                HTMLTextView(html: item.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
                    .navigationTitle("How I answered this")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                activeGutsContent = nil
                            }
                        }
                    }
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let isExpanded: Bool
    let onToggleGuts: () -> Void

    var isUser: Bool { message.sender == .user }
    var isSystem: Bool { message.sender == .system }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            bubbleBody
                .padding(12)
                .background(backgroundShape)

            if !isUser { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bubbleBody: some View {
        switch message.payloadType {
        case .gutslink:
            Button(action: onToggleGuts) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                    Text(message.text)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

        case .guts:
            EmptyView()

        case .chart:
            if let json = message.chartSpecJSON,
               let data = json.data(using: .utf8),
               let aiSpec = try? JSONDecoder().decode(AIChartSpec.self, from: data) {
                SparkChartView(spec: ChartNormalizer.build(from: aiSpec))
                    .frame(height: 220)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Chart unavailable")
                    .foregroundStyle(.secondary)
            }
        default:
            RichChatText(
                blocks: message.displayBlocks,
                fallbackText: message.text,
                foregroundStyle: isUser ? .white : (isSystem ? .secondary : .primary)
            )
            .multilineTextAlignment(.leading)
        }
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isUser {
            return BrandColors.teal
        }
        if isSystem {
            return Color(.tertiarySystemBackground)
        }
        switch message.payloadType {
        case .gutslink:
            return Color(.tertiarySystemBackground)
        case .guts:
            return Color(.secondarySystemBackground)
        case .chart:
            return Color(.secondarySystemBackground)
        case .error:
            return Color.red.opacity(0.12)
        default:
            return Color(.secondarySystemBackground)
        }
    }
}

private struct StatusPanel: View {
    let messages: [ChatMessage]

    private var progressFraction: CGFloat {
        let latestText = messages.last?.text ?? ""
        if latestText.localizedCaseInsensitiveContains("Building") {
            return 0.25
        } else if latestText.localizedCaseInsensitiveContains("Fetching") {
            return 0.50
        } else if latestText.localizedCaseInsensitiveContains("Analyzing the results") {
            return 0.75
        } else if messages.contains(where: { $0.payloadType == .success }) {
            return 1.0
        }
        return 0.12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let latest = messages.last {
                HStack(spacing: 10) {
                    Group {
                        switch latest.payloadType {
                        case .error:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        default:
                            ProgressView()
                        }
                    }

                    Text(latest.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)

                    Capsule()
                        .fill(BrandColors.teal)
                        .frame(width: max(12, geo.size.width * progressFraction), height: 6)
                        .animation(.easeInOut(duration: 0.25), value: progressFraction)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct RichChatText: View {
    let blocks: [ChatDisplayBlock]?
    let fallbackText: String
    let foregroundStyle: Color

    var body: some View {
        let resolvedBlocks = blocks ?? [
            ChatDisplayBlock(
                kind: .paragraph,
                plainText: fallbackText,
                attributedText: nil,
                tableData: nil
            )
        ]

        VStack(alignment: .leading, spacing: 8) {
            ForEach(resolvedBlocks) { block in
                switch block.kind {
                case .paragraph:
                    InlineMarkdownText(
                        plainText: block.plainText,
                        attributedText: block.attributedText,
                        foregroundStyle: foregroundStyle
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                case .bullet:
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(foregroundStyle)
                        InlineMarkdownText(
                            plainText: block.plainText,
                            attributedText: block.attributedText,
                            foregroundStyle: foregroundStyle
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .table:
                    if let table = block.tableData {
                        ChatTableView(table: table)
                    }
                }
            }
        }
    }
}

private struct ChatTableView: View {
    let table: ChatTableData

    private let cellWidth: CGFloat = 120

    private var columnCount: Int {
        max(
            table.headers.count,
            table.rows.map(\.count).max() ?? 0
        )
    }

    private func headerText(at index: Int) -> String {
        guard index < table.headers.count else { return "" }
        return table.headers[index]
    }

    private func cellText(in row: [String], at index: Int) -> String {
        guard index < row.count else { return "" }
        return row[index]
    }

    private var tableAsTSV: String {
        let headerLine = table.headers.joined(separator: "\t")
        let rowLines = table.rows.map { $0.joined(separator: "\t") }
        return ([headerLine] + rowLines).joined(separator: "\n")
    }

    private var tableAsCSV: String {
        func escape(_ value: String) -> String {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }

        let headerLine = table.headers.map(escape).joined(separator: ",")
        let rowLines = table.rows.map { row in
            row.map(escape).joined(separator: ",")
        }
        return ([headerLine] + rowLines).joined(separator: "\n")
    }

    private func makeCSVFile() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spark-table-\(UUID().uuidString).csv")

        do {
            try tableAsCSV.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Failed to write CSV:", error)
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { index in
                            Text(headerText(at: index))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: cellWidth, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                    }
                    .background(BrandColors.teal.opacity(0.10))

                    ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(0..<columnCount, id: \.self) { index in
                                Text(cellText(in: row, at: index))
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .frame(width: cellWidth, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                            }
                        }
                        .background(rowIndex.isMultiple(of: 2) ? Color(.secondarySystemBackground) : Color.clear)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = tableAsTSV
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                if let url = makeCSVFile() {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}

private struct InlineMarkdownText: View {
    let plainText: String
    let attributedText: AttributedString?
    let foregroundStyle: Color

    var body: some View {
        Group {
            if let attributedText {
                Text(attributedText)
            } else {
                Text(plainText)
            }
        }
        .foregroundStyle(foregroundStyle)
        .textSelection(.enabled)
    }
}


private struct GutsModalContent: Identifiable, Equatable {
    let text: String
    var id: String { text }
}

private struct HTMLTextView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let polishedHTML = preprocessHTML(html)
        let wrappedHTML = """
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
        <style>
        :root {
            color-scheme: light;
        }
        html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
            font-size: 15px;
            color: #111111;
            line-height: 1.45;
            -webkit-text-size-adjust: 100%;
            overflow-wrap: anywhere;
            word-break: break-word;
        }
        .intro {
            font-size: 17px;
            font-weight: 600;
            line-height: 1.4;
            margin: 0 0 14px 0;
        }
        .chips {
            margin: 0;
            padding: 0;
        }
        .chip {
            display: inline-block;
            background: #eef7f8;
            color: #1b1b1b;
            border: 1px solid #cfe7ea;
            border-radius: 999px;
            padding: 6px 10px;
            margin: 0 8px 8px 0;
            font-size: 14px;
            line-height: 1.3;
        }
        code, pre {
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 13px;
            white-space: pre-wrap;
        }
        a {
            color: #00737e;
            text-decoration: underline;
        }
        </style>
        </head>
        <body>
        \(polishedHTML)
        </body>
        </html>
        """

        if webView.url == nil || webView.isLoading == false {
            webView.loadHTMLString(wrappedHTML, baseURL: URL(string: "https://data.indianarealtors.com"))
        }
    }

    private func preprocessHTML(_ html: String) -> String {
        let working = html.trimmingCharacters(in: .whitespacesAndNewlines)

        if let ulRange = working.range(of: "<ul>", options: .caseInsensitive) {
            let intro = working[..<ulRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let listPart = String(working[ulRange.lowerBound...])

            var chips = listPart
            chips = chips.replacingOccurrences(of: "<ul>", with: "<div class=\"chips\">", options: .caseInsensitive)
            chips = chips.replacingOccurrences(of: "</ul>", with: "</div>", options: .caseInsensitive)
            chips = chips.replacingOccurrences(of: "<li>", with: "<span class=\"chip\">", options: .caseInsensitive)
            chips = chips.replacingOccurrences(of: "</li>", with: "</span>", options: .caseInsensitive)

            let introHTML = intro.isEmpty ? "" : "<div class=\"intro\">\(intro)</div>"
            return introHTML + chips
        }

        return "<div class=\"intro\">\(working)</div>"
    }
}

private struct AIChartSpec: Decodable {
    let chartType: String?
    let labels: [String]?
    let title: String?
    let datasets: [AIChartDataset]?

    enum CodingKeys: String, CodingKey {
        case chartType = "chart_type"
        case labels
        case title
        case datasets
    }
}

private struct AIChartDataset: Decodable {
    let label: String?
    let data: [Double]?
    let borderWidth: Double?
    let tension: Double?
    let pointRadius: Double?
    let fill: Bool?
    let borderColor: String?
    let backgroundColor: String?

    enum CodingKeys: String, CodingKey {
        case label
        case data
        case borderWidth
        case tension
        case pointRadius
        case fill
        case borderColor
        case backgroundColor
    }
}

private enum ChartKind: String {
    case line
    case bar
}

private struct NormalizedChartSpec {
    let chartType: ChartKind
    let title: String?
    let series: [NormalizedSeries]
}

private struct NormalizedSeries: Identifiable {
    let id = UUID()
    let label: String
    let points: [ChartPoint]
    let lineWidth: Double
    let pointRadius: Double
    let fill: Bool
    let color: Color
    let fillColor: Color
}

private struct ChartPoint: Identifiable {
    let id = UUID()
    let xLabel: String
    let yValue: Double
}

private enum ChartNormalizer {
    static let baseColors: [Color] = [
        BrandColors.teal,
        .blue,
        .purple,
        .orange,
        .pink,
        .green
    ]

    static func build(from spec: AIChartSpec) -> NormalizedChartSpec {
        let labels = spec.labels ?? []
        let chartType = ChartKind(rawValue: spec.chartType ?? "") ?? .line

        let series: [NormalizedSeries] = (spec.datasets ?? []).enumerated().map { index, ds in
            let base = baseColors[index % baseColors.count]
            let values = ds.data ?? []
            let points = zip(labels, values).map { label, value in
                ChartPoint(xLabel: label, yValue: value)
            }

            return NormalizedSeries(
                label: ds.label ?? "Series \(index + 1)",
                points: points,
                lineWidth: ds.borderWidth ?? 2,
                pointRadius: ds.pointRadius ?? 0,
                fill: ds.fill ?? false,
                color: base,
                fillColor: base.opacity(0.2)
            )
        }

        return NormalizedChartSpec(
            chartType: chartType,
            title: spec.title,
            series: series
        )
    }
}

private struct SparkChartView: View {
    let spec: NormalizedChartSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = spec.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            Chart {
                ForEach(spec.series) { series in
                    if spec.chartType == .line, series.fill {
                        ForEach(series.points) { point in
                            AreaMark(
                                x: .value("Label", point.xLabel),
                                y: .value(series.label, point.yValue)
                            )
                            .foregroundStyle(series.fillColor)
                        }
                    }

                    ForEach(series.points) { point in
                        switch spec.chartType {
                        case .line:
                            LineMark(
                                x: .value("Label", point.xLabel),
                                y: .value(series.label, point.yValue)
                            )
                            .foregroundStyle(series.color)
                            .lineStyle(StrokeStyle(lineWidth: series.lineWidth))

                            if series.pointRadius > 0 {
                                PointMark(
                                    x: .value("Label", point.xLabel),
                                    y: .value(series.label, point.yValue)
                                )
                                .foregroundStyle(series.color)
                            }

                        case .bar:
                            BarMark(
                                x: .value("Label", point.xLabel),
                                y: .value(series.label, point.yValue)
                            )
                            .foregroundStyle(series.color)
                        }
                    }
                }
            }
            .chartLegend(.visible)
        }
    }
}
