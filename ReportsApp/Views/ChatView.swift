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
        .navigationTitle("Spark")
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
                ChartCardView(spec: ChartNormalizer.build(from: aiSpec))
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

private struct ChartShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private enum ChartExportLayout: String, CaseIterable, Identifiable {
    case post
    case square
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .post:
            return "Post"
        case .square:
            return "Square"
        case .story:
            return "Story"
        }
    }

    var systemImage: String {
        switch self {
        case .post:
            return "rectangle.portrait"
        case .square:
            return "square"
        case .story:
            return "rectangle"
        }
    }

    var size: CGSize {
        switch self {
        case .post:
            return CGSize(width: 1080, height: 1350)
        case .square:
            return CGSize(width: 1080, height: 1080)
        case .story:
            return CGSize(width: 1080, height: 1920)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .post:
            return 56
        case .square:
            return 48
        case .story:
            return 56
        }
    }

    var topPadding: CGFloat {
        switch self {
        case .post:
            return 52
        case .square:
            return 48
        case .story:
            return 64
        }
    }

    var bottomPadding: CGFloat {
        switch self {
        case .post:
            return 40
        case .square:
            return 40
        case .story:
            return 48
        }
    }

    var chartTopPadding: CGFloat {
        switch self {
        case .post:
            return 80
        case .square:
            return 64
        case .story:
            return 92
        }
    }

    var chartHeightRatio: CGFloat {
        switch self {
        case .post:
            return 0.56
        case .square:
            return 0.50
        case .story:
            return 0.48
        }
    }

    var titleFontSize: CGFloat {
        switch self {
        case .post:
            return 58
        case .square:
            return 52
        case .story:
            return 60
        }
    }

    var subtitleFontSize: CGFloat {
        switch self {
        case .post:
            return 30
        case .square:
            return 28
        case .story:
            return 30
        }
    }

    var footerFontSize: CGFloat {
        switch self {
        case .post:
            return 26
        case .square:
            return 26
        case .story:
            return 26
        }
    }
}

private struct ChartCardView: View {
    let spec: NormalizedChartSpec
    @Environment(\.displayScale) private var displayScale

    @State private var shareItem: ChartShareItem?
    @State private var showingExpandedChart = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SparkChartView(spec: spec)
                .frame(height: 240)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                Button {
                    if let image = renderChartImage(height: 220) {
                        UIPasteboard.general.image = image
                        didCopy = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(1200))
                            didCopy = false
                        }
                    }
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(ChartExportLayout.allCases) { layout in
                        Button {
                            if let image = renderExportImage(layout: layout) {
                                shareItem = ChartShareItem(image: image)
                            }
                        } label: {
                            Label(layout.title, systemImage: layout.systemImage)
                        }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }

                Button {
                    showingExpandedChart = true
                } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)
        }
        .sheet(item: $shareItem) { item in
            ChartActivityView(activityItems: [item.image])
        }
        .sheet(isPresented: $showingExpandedChart) {
            NavigationStack {
                ScrollView {
                    SparkChartView(spec: spec)
                        .frame(height: 360)
                        .padding()
                }
                .navigationTitle(spec.title ?? "Chart")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showingExpandedChart = false
                        }
                    }
                }
            }
        }
    }

    private func renderChartImage(height: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(
            content: SparkChartView(spec: spec)
                .frame(width: 700, height: height)
                .padding(16)
                .background(Color(.systemBackground))
        )
        renderer.scale = displayScale
        return renderer.uiImage
    }

    private func renderExportImage(layout: ChartExportLayout) -> UIImage? {
        let width = layout.size.width
        let height = layout.size.height
        let horizontalPadding = layout.horizontalPadding
        let topPadding = layout.topPadding
        let bottomPadding = layout.bottomPadding
        let chartTopPadding = layout.chartTopPadding
        let chartHeight = height * layout.chartHeightRatio

        let renderer = ImageRenderer(
            content: VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    if let title = spec.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: layout.titleFontSize, weight: .bold, design: .default))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(layout == .story ? 4 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let subtitle = spec.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: layout.subtitleFontSize, weight: .regular, design: .default))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)

                SparkChartView(spec: spec, showsHeader: false, isExportStyle: true)
                    .frame(height: chartHeight)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, chartTopPadding)

                Spacer(minLength: 0)

                Text("Source: Indiana Association of REALTORS® | Housing Hub")
                    .font(.system(size: layout.footerFontSize, weight: .regular, design: .default))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, bottomPadding)
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .background(Color(.systemBackground))
        )
        renderer.scale = displayScale
        return renderer.uiImage
    }
}

private struct ChartActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.bottom, 6)
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
                tableData: nil,
                relatedLinks: []
            )
        ]

        VStack(alignment: .leading, spacing: 8) {
            ForEach(resolvedBlocks) { block in
                switch block.kind {
                case .paragraph:
                    VStack(alignment: .leading, spacing: 8) {
                        InlineMarkdownText(
                            plainText: block.plainText,
                            attributedText: block.attributedText,
                            foregroundStyle: foregroundStyle
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let relatedLinks = block.relatedLinks, !relatedLinks.isEmpty {
                            RelatedLinksView(links: relatedLinks)
                        }
                    }

                case .bullet:
                    VStack(alignment: .leading, spacing: 8) {
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

                        if let relatedLinks = block.relatedLinks, !relatedLinks.isEmpty {
                            RelatedLinksView(links: relatedLinks)
                                .padding(.leading, 18)
                        }
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

private enum RelatedLinkKind {
    case chart
    case report
    case link

    init(urlString: String) {
        let lower = urlString.lowercased()
        if lower.contains("reports/viz/") {
            self = .chart
        } else if lower.contains("reports/viewreport") {
            self = .report
        } else {
            self = .link
        }
    }

    var title: String {
        switch self {
        case .chart:
            return "Chart"
        case .report:
            return "Report"
        case .link:
            return "Link"
        }
    }

    var systemImage: String {
        switch self {
        case .chart:
            return "chart.xyaxis.line"
        case .report:
            return "doc.text"
        case .link:
            return "link"
        }
    }

    var tint: Color {
        switch self {
        case .chart:
            return BrandColors.teal
        case .report:
            return Color(hex: "#433277")
        case .link:
            return Color(hex: "#e77c05")
        }
    }
}

private struct RelatedLinksView: View {
    let links: [ChatRelatedLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                if let url = URL(string: link.urlString) {
                    Link(destination: url) {
                        RelatedLinkCard(link: link)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct RelatedLinkCard: View {
    let link: ChatRelatedLink

    private var kind: RelatedLinkKind {
        RelatedLinkKind(urlString: link.urlString)
    }

    private var hostLabel: String {
        URL(string: link.urlString)?.host ?? "data.indianarealtors.com"
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(kind.tint.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(kind.tint)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(link.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text(kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(kind.tint)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(hostLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
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
    let subtitle: String?
    let datasets: [AIChartDataset]?

    enum CodingKeys: String, CodingKey {
        case chartType = "chart_type"
        case labels
        case title
        case subtitle
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
    let subtitle: String?
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

private let chartBrandColors: [Color] = [
    Color(hex: "#00737e"),
    Color(hex: "#e77c05"),
    Color(hex: "#95215e"),
    Color(hex: "#433277")
]

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch cleaned.count {
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 115, 126)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

private enum ChartNormalizer {
    static func build(from spec: AIChartSpec) -> NormalizedChartSpec {
        let labels = spec.labels ?? []
        let chartType = ChartKind(rawValue: spec.chartType ?? "") ?? .line

        let series: [NormalizedSeries] = (spec.datasets ?? []).enumerated().map { index, ds in
            let baseColor = ds.borderColor.map(Color.init(hex:)) ?? chartBrandColors[index % chartBrandColors.count]
            let values = ds.data ?? []

            let points = zip(labels, values).map { label, value in
                ChartPoint(xLabel: label, yValue: value)
            }

            return NormalizedSeries(
                label: ds.label ?? "Series \(index + 1)",
                points: points,
                lineWidth: ds.borderWidth ?? 4,
                pointRadius: ds.pointRadius ?? 4,
                fill: ds.fill ?? false,
                color: baseColor,
                fillColor: baseColor.opacity(ds.fill ?? false ? 0.18 : 0.85)
            )
        }

        return NormalizedChartSpec(
            chartType: chartType,
            title: spec.title,
            subtitle: spec.subtitle,
            series: series
        )
    }
}

private struct SparkChartView: View {
    let spec: NormalizedChartSpec
    var showsHeader: Bool = true
    var isExportStyle: Bool = false

    private enum AxisLabelKind {
        case categorical
        case monthly
        case weekly
    }

    private func axisLabelKind(for labels: [String]) -> AxisLabelKind {
        if let subtitle = spec.subtitle?.lowercased(), subtitle.contains("week") {
            return .weekly
        }

        guard let sample = labels.first?.lowercased() else { return .categorical }

        if sample.contains("week of") {
            return .weekly
        }

        let monthTokens = [
            "jan", "feb", "mar", "apr", "may", "jun",
            "jul", "aug", "sep", "sept", "oct", "nov", "dec"
        ]

        if monthTokens.contains(where: { sample.contains($0) }) {
            return .monthly
        }

        return .categorical
    }

    private func periodicAnchorLabels(from labels: [String], every period: Int) -> [String] {
        guard !labels.isEmpty else { return [] }
        guard period > 0 else { return labels }

        var output: [String] = []
        var index = 0
        while index < labels.count {
            output.append(labels[index])
            index += period
        }

        return output
    }

    private func visibleXAxisLabels() -> [String] {
        guard let labels = spec.series.first?.points.map(\.xLabel), !labels.isEmpty else { return [] }

        let kind = axisLabelKind(for: labels)

        switch kind {
        case .categorical:
            return labels

        case .monthly:
            if labels.count < 6 {
                return labels
            } else if labels.count < 18 {
                return periodicAnchorLabels(from: labels, every: 3)
            } else {
                return periodicAnchorLabels(from: labels, every: 12)
            }

        case .weekly:
            if labels.count < 104 {
                if labels.count <= 2 {
                    return labels
                }
                return [labels.first!, labels.last!]
            } else {
                return periodicAnchorLabels(from: labels, every: 52)
            }
        }
    }

    private var isLongMonthlySeries: Bool {
        guard let labels = spec.series.first?.points.map(\.xLabel), !labels.isEmpty else { return false }
        return axisLabelKind(for: labels) == .monthly && labels.count >= 18
    }

    private func compactXAxisLabel(_ label: String, visibleLabels: [String]) -> String {
        guard isLongMonthlySeries else { return label }

        let monthTokens = [
            "jan", "feb", "mar", "apr", "may", "jun",
            "jul", "aug", "sep", "sept", "oct", "nov", "dec"
        ]

        let visibleLower = visibleLabels.map { $0.lowercased() }
        let sharedMonth = monthTokens.first { token in
            visibleLower.allSatisfy { $0.contains(token) }
        }

        let parts = label.split(separator: " ")
        guard let yearPart = parts.last, yearPart.count == 4 else { return label }
        let year = String(yearPart.suffix(2))

        if sharedMonth != nil {
            return "’\(year)"
        }

        if let month = parts.first {
            return "\(month) ’\(year)"
        }

        return label
    }

    private var chartEndPadding: CGFloat {
        if isExportStyle, visibleXAxisLabels().count > 2 {
            return 84
        }
        return isExportStyle ? 40 : 12
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chartHeader
            chartLegendView
            chartContent
        }
    }
    @ViewBuilder
    private var chartLegendView: some View {
        if spec.series.count > 1 {
            HStack(spacing: isExportStyle ? 20 : 14) {
                ForEach(spec.series) { series in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(series.color)
                            .frame(width: isExportStyle ? 16 : 10, height: isExportStyle ? 16 : 10)

                        Text(series.label)
                            .font(isExportStyle ? .system(size: 26, weight: .semibold) : .caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, isExportStyle ? 14 : 0)
        }
    }

    @ViewBuilder
    private var chartHeader: some View {
        if showsHeader, let title = spec.title, !title.isEmpty {
            Text(title)
                .font(.subheadline.weight(.semibold))
        }

        if showsHeader, let subtitle = spec.subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(spec.series) { series in
                seriesMarks(for: series)
            }
        }
        .chartXAxis { xAxisMarks }
        .chartXScale(range: .plotDimension(startPadding: isExportStyle ? 40 : 12, endPadding: chartEndPadding))
        .chartYAxis { yAxisMarks }
        .chartLegend(.hidden)
    }

    @ChartContentBuilder
    private func seriesMarks(for series: NormalizedSeries) -> some ChartContent {
        if spec.chartType == .line, series.fill {
            ForEach(series.points) { point in
                AreaMark(
                    x: .value("Label", point.xLabel),
                    y: .value("Value", point.yValue),
                    series: .value("Series", series.label)
                )
                .foregroundStyle(series.fillColor)
            }
        }

        ForEach(series.points) { point in
            primaryMark(for: point, in: series)
        }

        if spec.chartType == .line, let first = series.points.first {
            PointMark(
                x: .value("Label", first.xLabel),
                y: .value("Value", first.yValue)
            )
            .foregroundStyle(series.color)
            .symbolSize(isExportStyle ? 160 : 85)
        }

        if spec.chartType == .line,
           let last = series.points.last,
           last.id != series.points.first?.id {
            PointMark(
                x: .value("Label", last.xLabel),
                y: .value("Value", last.yValue)
            )
            .foregroundStyle(series.color)
            .symbolSize(isExportStyle ? 160 : 85)
        }
    }

    @ChartContentBuilder
    private func primaryMark(for point: ChartPoint, in series: NormalizedSeries) -> some ChartContent {
        switch spec.chartType {
        case .line:
            LineMark(
                x: .value("Label", point.xLabel),
                y: .value("Value", point.yValue),
                series: .value("Series", series.label)
            )
            .foregroundStyle(series.color)
            .lineStyle(
                StrokeStyle(
                    lineWidth: isExportStyle ? max(series.lineWidth, 10) : series.lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

        case .bar:
            BarMark(
                x: .value("Label", point.xLabel),
                y: .value("Value", point.yValue)
            )
            .foregroundStyle(series.color)
        }
    }

    private var xAxisMarks: some AxisContent {
        let visible = visibleXAxisLabels()
        let lastVisible = visible.last
        let shouldLeftAnchorLast = visible.count > 2 && !isLongMonthlySeries

        return AxisMarks(values: visible) { value in
            AxisGridLine()
                .foregroundStyle(Color.primary.opacity(isExportStyle ? 0.30 : 0.20))

            AxisTick()
                .foregroundStyle(Color.primary.opacity(0.12))

            if let label = value.as(String.self) {
                if shouldLeftAnchorLast, label == lastVisible {
                    AxisValueLabel(anchor: .topLeading) {
                        Text(compactXAxisLabel(label, visibleLabels: visible))
                            .font(isExportStyle ? .system(size: 28, weight: .medium) : .caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                } else {
                    AxisValueLabel(centered: false) {
                        Text(compactXAxisLabel(label, visibleLabels: visible))
                            .font(isExportStyle ? .system(size: 28, weight: .medium) : .caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
    }

    private var yAxisMarks: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine()
                .foregroundStyle(Color.primary.opacity(isExportStyle ? 0.30 : 0.20))
            AxisTick()
                .foregroundStyle(Color.primary.opacity(0.12))
            AxisValueLabel() {
                if let number = value.as(Double.self) {
                    Text(number.formatted())
                        .font(isExportStyle ? .system(size: 28, weight: .medium) : .caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
