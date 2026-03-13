//
//  ChatView.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/13/26.
//


import SwiftUI
import WebKit

struct ChatView: View {
    @StateObject private var chat = ChatManager()
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
                    LazyVStack(alignment: .leading, spacing: 12) {
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
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .top)
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask about the market…", text: $chat.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)

                Button {
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

        default:
            RichChatText(
                text: message.text,
                foregroundStyle: isUser ? .white : (isSystem ? .secondary : .primary),
                preserveStructure: !isUser && !isSystem
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
    let text: String
    let foregroundStyle: Color
    let preserveStructure: Bool

    private var normalizedText: String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
    }

    private var blocks: [ChatTextBlock] {
        guard preserveStructure else {
            return [.paragraph(normalizedText)]
        }

        let lines = normalizedText.components(separatedBy: "\n")
        var result: [ChatTextBlock] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            let paragraph = paragraphBuffer
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph))
            }
            paragraphBuffer.removeAll()
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if line.hasPrefix("- ") {
                flushParagraph()
                let bulletText = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(.bullet(bulletText))
            } else {
                paragraphBuffer.append(rawLine)
            }
        }

        flushParagraph()
        return result.isEmpty ? [.paragraph(normalizedText)] : result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let paragraph):
                    InlineMarkdownText(
                        text: paragraph,
                        foregroundStyle: foregroundStyle
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .bullet(let bullet):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(foregroundStyle)
                        InlineMarkdownText(
                            text: bullet,
                            foregroundStyle: foregroundStyle
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct InlineMarkdownText: View {
    let text: String
    let foregroundStyle: Color

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible,
                languageCode: nil
            )
        ) {
            Text(attributed)
                .foregroundStyle(foregroundStyle)
                .textSelection(.enabled)
        } else {
            Text(text)
                .foregroundStyle(foregroundStyle)
                .textSelection(.enabled)
        }
    }
}

private enum ChatTextBlock {
    case paragraph(String)
    case bullet(String)
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
