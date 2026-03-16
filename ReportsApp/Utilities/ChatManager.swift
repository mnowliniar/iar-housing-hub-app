//
//  ChatManager.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/13/26.
//


import Foundation
import SwiftUI

@MainActor
final class ChatManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isSending = false
    @Published var conversationName: String?
    @Published var statusText: String?
    @Published var statusMessages: [ChatMessage] = []
    @Published var pendingScrollTarget: UUID?
    @Published var chats: [ChatSummary] = []
    @Published var isLoadingChats = false
    @Published var chatListError: String?
    private var lastUserMessageID: UUID?

    @AppStorage("currentChatThreadID") private var storedThreadID: String = ""

    private let baseURL = "https://data.indianarealtors.com"
    private var pollingTask: Task<Void, Never>?

    var threadID: String {
        if storedThreadID.isEmpty {
            storedThreadID = UUID().uuidString
        }
        return storedThreadID
    }
    func fetchChats(anonymousThreadIDs: [String] = []) async {
        isLoadingChats = true
        chatListError = nil

        do {
            chats = try await listChats(anonymousThreadIDs: anonymousThreadIDs)
        } catch {
            chatListError = error.localizedDescription
        }

        isLoadingChats = false
    }

    private func listChats(anonymousThreadIDs: [String]) async throws -> [ChatSummary] {
        let url = URL(string: "\(baseURL)/list_chats/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "filenames": anonymousThreadIDs
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "Unable to load chats."
            throw NSError(
                domain: "ChatManager",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        let decoded = try JSONDecoder().decode(ListChatsResponse.self, from: data)
        return decoded.chats
    }
    private struct ListChatsResponse: Decodable {
        let chats: [ChatSummary]
    }
    func newChat() {
        pollingTask?.cancel()
        storedThreadID = UUID().uuidString
        messages = []
        inputText = ""
        conversationName = nil
        pendingScrollTarget = nil
        lastUserMessageID = nil
        resetStatusState()
    }

    func sendCurrentMessage() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }

        inputText = ""
        let userMessage = ChatMessage(
            sender: .user,
            text: prompt,
            displayBlocks: buildDisplayBlocks(from: prompt, enableInlineMarkdown: false, preserveStructure: false)
        )
        messages.append(userMessage)
        lastUserMessageID = userMessage.id
        await send(prompt: prompt)
    }

    func send(prompt: String) async {
        isSending = true
        statusMessages = [
            ChatMessage(
                sender: .system,
                text: "Analyzing your question",
                payloadType: .status,
                isEphemeral: true
            )
        ]
        statusText = "Analyzing your question"

        do {
            let uniqueID = try await generateUniqueID()
            let initial = try await handleUserQuery(
                prompt: prompt,
                uniqueID: uniqueID,
                threadID: threadID
            )

            conversationName = initial.conversationName

            appendBackendMessages(initial.messages, sender: .assistant)

            if let filename = initial.filename, !filename.isEmpty {
                pollingTask?.cancel()
                pollingTask = Task { [weak self] in
                    await self?.pollStatus(uniqueID: uniqueID)
                }

                let final = try await executeSQL(
                    filename: filename,
                    uniqueID: uniqueID,
                    threadID: threadID
                )

                pollingTask?.cancel()
                removeEphemeralMessages()
                appendBackendMessages(final.messages, sender: .assistant)
            } else {
                removeEphemeralMessages()
            }

            resetStatusState()
            isSending = false
            pendingScrollTarget = lastUserMessageID
        } catch {
            print("[Chat] send(prompt:) failed:", error)

            let messageText: String
            if let decodingError = error as? DecodingError {
                messageText = "Something went wrong reading the response from Spark.\n\n\(describeDecodingError(decodingError))"
            } else {
                messageText = "Something went wrong sending your message.\n\n\(error.localizedDescription)"
            }

            removeEphemeralMessages()
            messages.append(
                ChatMessage(
                    sender: .system,
                    text: messageText,
                    payloadType: .error,
                    displayBlocks: buildDisplayBlocks(from: messageText, enableInlineMarkdown: false, preserveStructure: false)
                )
            )
            resetStatusState()
            isSending = false
            pendingScrollTarget = lastUserMessageID
        }
    }

    private func generateUniqueID() async throws -> String {
        let url = URL(string: "\(baseURL)/generate_unique_id")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(GenerateUniqueIDResponse.self, from: data)
        return decoded.uniqueID
    }

    private func handleUserQuery(
        prompt: String,
        uniqueID: String,
        threadID: String
    ) async throws -> HandleUserQueryResponse {
        var components = URLComponents(string: "\(baseURL)/handle_user_query")!
        components.queryItems = [
            URLQueryItem(name: "prompt", value: prompt),
            URLQueryItem(name: "unique_id", value: uniqueID),
            URLQueryItem(name: "thread_id", value: threadID)
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(HandleUserQueryResponse.self, from: data)
    }

    private func executeSQL(
        filename: String,
        uniqueID: String,
        threadID: String
    ) async throws -> ExecuteSQLResponse {
        var components = URLComponents(string: "\(baseURL)/execute_sql")!
        components.queryItems = [
            URLQueryItem(name: "filename", value: filename),
            URLQueryItem(name: "unique_id", value: uniqueID),
            URLQueryItem(name: "thread_id", value: threadID)
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)

        if let http = response as? HTTPURLResponse {
            print("[Chat] executeSQL status:", http.statusCode)
        }
        if let raw = String(data: data, encoding: .utf8) {
            print("[Chat] executeSQL raw response:", raw)
        }

        return try JSONDecoder().decode(ExecuteSQLResponse.self, from: data)
    }

    private func checkStatus(uniqueID: String) async throws -> CheckStatusResponse {
        var components = URLComponents(string: "\(baseURL)/check_status")!
        components.queryItems = [URLQueryItem(name: "unique_id", value: uniqueID)]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(CheckStatusResponse.self, from: data)
    }

    private func pollStatus(uniqueID: String) async {
        while !Task.isCancelled {
            do {
                let response = try await checkStatus(uniqueID: uniqueID)
                updateEphemeralMessages(from: response.messages)
            } catch {
                break
            }

            try? await Task.sleep(nanoseconds: 900_000_000)
        }
    }

    private func appendBackendMessages(
        _ backendMessages: [BackendChatMessage],
        sender: ChatSender
    ) {
        for item in backendMessages {
            let payload = ChatPayloadType(rawValue: item.type)
            let text = item.body.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            switch payload {
            case .status, .success, .hidden:
                continue
            case .chart:
                messages.append(
                    ChatMessage(
                        sender: .assistant,
                        text: "",
                        payloadType: payload,
                        chartSpecJSON: text
                    )
                )
            default:
                messages.append(
                    ChatMessage(
                        sender: sender,
                        text: text,
                        payloadType: payload,
                        displayBlocks: buildDisplayBlocks(
                            from: text,
                            enableInlineMarkdown: sender == .assistant && payload != .gutslink,
                            preserveStructure: sender == .assistant && payload != .gutslink
                        )
                    )
                )
            }
        }
    }

    private func updateEphemeralMessages(from backendMessages: [BackendChatMessage]) {
        let ephemeral = backendMessages.compactMap { item -> ChatMessage? in
            let payload = ChatPayloadType(rawValue: item.type)
            let text = item.body.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            switch payload {
            case .status, .success, .error:
                return ChatMessage(
                    sender: .system,
                    text: text,
                    payloadType: payload,
                    isEphemeral: true,
                    displayBlocks: buildDisplayBlocks(from: text, enableInlineMarkdown: false, preserveStructure: false)
                )
            default:
                return nil
            }
        }

        statusMessages = ephemeral
        statusText = ephemeral.last?.text
    }

    private func removeEphemeralMessages() {
        statusMessages = []
        messages.removeAll { $0.isEphemeral }
    }
    
    private func resetStatusState() {
        statusMessages = []
        statusText = nil
    }

    private struct ParsedInternalLink: Hashable {
        let title: String
        let href: String
    }

    private func normalizedInternalURLString(from href: String) -> String {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.hasPrefix("/") {
            return "\(baseURL)\(trimmed)"
        }
        return "\(baseURL)/\(trimmed)"
    }

    private func extractMarkdownLinks(from text: String) -> [ParsedInternalLink] {
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { match in
            guard match.numberOfRanges == 3 else { return nil }
            let title = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let href = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !href.isEmpty else { return nil }
            return ParsedInternalLink(title: title, href: normalizedInternalURLString(from: href))
        }
    }

    private func expandMarkdownLinksToAbsoluteURLs(in text: String) -> String {
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed()
        var output = text

        for match in matches {
            guard match.numberOfRanges == 3 else { continue }
            let title = nsText.substring(with: match.range(at: 1))
            let href = nsText.substring(with: match.range(at: 2))
            let replacement = "[\(title)](\(normalizedInternalURLString(from: href)))"
            if let range = Range(match.range(at: 0), in: output) {
                output.replaceSubrange(range, with: replacement)
            }
        }

        return output
    }

    private func buildDisplayBlocks(
        from text: String,
        enableInlineMarkdown: Bool,
        preserveStructure: Bool
    ) -> [ChatDisplayBlock] {
        let normalizedText = text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")

        let expandedText = enableInlineMarkdown ? expandMarkdownLinksToAbsoluteURLs(in: normalizedText) : normalizedText

        guard preserveStructure else {
            return [
                ChatDisplayBlock(
                    kind: .paragraph,
                    plainText: expandedText,
                    attributedText: makeInlineMarkdown(expandedText, enabled: enableInlineMarkdown),
                    tableData: nil,
                    relatedLinks: extractMarkdownLinks(from: expandedText).map {
                        ChatRelatedLink(
                            title: $0.title,
                            urlString: $0.href
                        )
                    }
                )
            ]
        }

        let lines = expandedText.components(separatedBy: "\n")

        func isTableSeparator(_ line: String) -> Bool {
            let trimmed = line.replacingOccurrences(of: " ", with: "")
            return trimmed.contains("|-")
        }

        var result: [ChatDisplayBlock] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            let paragraph = paragraphBuffer
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !paragraph.isEmpty {
                let relatedLinks = extractMarkdownLinks(from: paragraph)
                result.append(
                    ChatDisplayBlock(
                        kind: .paragraph,
                        plainText: paragraph,
                        attributedText: makeInlineMarkdown(paragraph, enabled: enableInlineMarkdown),
                        tableData: nil,
                        relatedLinks: relatedLinks.map {
                            ChatRelatedLink(
                                title: $0.title,
                                urlString: $0.href
                            )
                        }
                    )
                )
            }
            paragraphBuffer.removeAll()
        }

        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if line.contains("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                flushParagraph()

                let headers = rawLine
                    .split(separator: "|", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                var rows: [[String]] = []
                var rowIndex = index + 2

                while rowIndex < lines.count {
                    let rowLine = lines[rowIndex].trimmingCharacters(in: .whitespaces)
                    if rowLine.isEmpty || !rowLine.contains("|") {
                        break
                    }

                    let cells = lines[rowIndex]
                        .split(separator: "|", omittingEmptySubsequences: true)
                        .map { $0.trimmingCharacters(in: .whitespaces) }

                    if !cells.isEmpty {
                        rows.append(cells)
                    }
                    rowIndex += 1
                }

                if !headers.isEmpty {
                    result.append(
                        ChatDisplayBlock(
                            kind: .table,
                            plainText: "",
                            attributedText: nil,
                            tableData: ChatTableData(headers: headers, rows: rows),
                            relatedLinks: nil
                        )
                    )
                }

                index = rowIndex
                continue
            }

            if line.hasPrefix("- ") {
                flushParagraph()
                let bulletText = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(
                    ChatDisplayBlock(
                        kind: .bullet,
                        plainText: bulletText,
                        attributedText: makeInlineMarkdown(bulletText, enabled: enableInlineMarkdown),
                        tableData: nil,
                        relatedLinks: extractMarkdownLinks(from: bulletText).map {
                            ChatRelatedLink(
                                title: $0.title,
                                urlString: $0.href
                            )
                        }
                    )
                )
            } else {
                paragraphBuffer.append(rawLine)
            }

            index += 1
        }

        flushParagraph()

        if result.isEmpty {
            return [
                ChatDisplayBlock(
                    kind: .paragraph,
                    plainText: expandedText,
                    attributedText: makeInlineMarkdown(expandedText, enabled: enableInlineMarkdown),
                    tableData: nil,
                    relatedLinks: extractMarkdownLinks(from: expandedText).map {
                        ChatRelatedLink(
                            title: $0.title,
                            urlString: $0.href
                        )
                    }
                )
            ]
        }

        return result
    }

    private func makeInlineMarkdown(_ text: String, enabled: Bool) -> AttributedString? {
        guard enabled else { return nil }
        return try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible,
                languageCode: nil
            )
        )
    }
    private func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "Spark returned a value of the wrong type for \(type).\n\(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Spark left out a required value for \(type).\n\(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "Spark left out the field '\(key.stringValue)'.\n\(context.debugDescription)"
        case .dataCorrupted(let context):
            return "Spark returned data in a format the app could not read.\n\(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}
