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
    /// More chats exist before the loaded ones ("Show older chats").
    @Published var hasOlderChats = false
    private var olderChatsCursor: String?
    /// The answer as it streams in: the opening line, then the prose tokens.
    /// Both clear when the final result replaces them.
    @Published var streamingPreamble: String = ""
    @Published var streamingTokens: String = ""
    /// The repeat-request offer that came with the last answer, if any.
    @Published var repeatOffer: RepeatOffer?
    /// What the last answer was, for the follow-up chip.
    @Published var lastAnswerHadData = false
    @Published var lastAnswerText: String?
    /// One suggested next question under the last answer, like the web's chip.
    @Published var followUpChip: String?
    /// Confirmation or error after the member answers the repeat offer.
    @Published var repeatOfferStatus: String?
    @Published var isAcceptingRepeatOffer = false
    private var lastUserMessageID: UUID?
    /// The question behind the last answer. Accepting a repeat offer saves it
    /// as the recipe.
    private var lastPrompt: String?

    /// Live preview text while an answer streams, or nil when there is none.
    var streamingText: String? {
        let parts = [streamingPreamble, streamingTokens]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    @AppStorage("currentChatThreadID") private var storedThreadID: String = ""

    /// Static so views that make their own one-off calls (one-sheet download)
    /// share the origin instead of hardcoding a second copy.
    static let serverBaseURL = "https://data.indianarealtors.com"
    private let baseURL = ChatManager.serverBaseURL
    private var pollingTask: Task<Void, Never>?

    /// Lowercase, like the web's. The web's chat pages (report, slides,
    /// files) only accept lowercase ids, and the pin and chat files are keyed
    /// by the exact string, so an uppercase app id could never be opened
    /// there.
    static func newThreadID() -> String { UUID().uuidString.lowercased() }

    /// The web's report and slides editors can open this chat once it has
    /// an answer. The server takes the uppercase ids older versions made.
    var canOpenOnWeb: Bool {
        !messages.isEmpty
    }

    /// A new chat screen starts empty, so it starts a new thread. The id used
    /// to outlive a relaunch while the messages didn't: the next question
    /// went into the old thread, with its pins and history, behind an empty
    /// screen. The old chat is still in the chat list.
    init() {
        storedThreadID = ""
    }

    var threadID: String {
        if storedThreadID.isEmpty {
            storedThreadID = Self.newThreadID()
        }
        return storedThreadID
    }
    /// First page of the chat list, as the web sidebar loads it: the last two
    /// weeks (at least the newest 8). Chats a schedule made are left out
    /// here and show up under Runs and in search.
    func fetchChats(anonymousThreadIDs: [String] = []) async {
        isLoadingChats = true
        chatListError = nil

        do {
            let page = try await listChats(["filenames": anonymousThreadIDs])
            chats = page.chats
            hasOlderChats = page.more ?? false
            olderChatsCursor = page.nextBefore
        } catch {
            chatListError = error.localizedDescription
        }

        isLoadingChats = false
    }

    /// "Show older chats": the next page before the last one loaded.
    func loadOlderChats() async {
        guard let before = olderChatsCursor, !isLoadingChats else { return }
        isLoadingChats = true
        defer { isLoadingChats = false }
        do {
            let page = try await listChats(["before": before])
            let known = Set(chats.map(\.id))
            chats += page.chats.filter { !known.contains($0.id) }
            hasOlderChats = page.more ?? false
            olderChatsCursor = page.nextBefore
        } catch {
            debugLog("[Chat] loadOlderChats failed:", error)
        }
    }

    /// Server-side search over every chat's name and first question,
    /// scheduled-run chats included, like the web's search box.
    func searchChats(_ query: String) async -> [ChatSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return (try? await listChats(["q": q, "limit": 50]).chats) ?? []
    }

    private func listChats(_ body: [String: Any]) async throws -> ListChatsResponse {
        // Identity rides the query string or the Bearer header; the server
        // never reads chat_user_id from a JSON body, so sending it there
        // left members with pre-token sessions an empty list.
        var components = URLComponents(string: "\(baseURL)/list_chats/")!
        if let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty {
            components.queryItems = [URLQueryItem(name: "chat_user_id", value: chatUserID)]
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload = body
        if payload["filenames"] == nil { payload["filenames"] = [String]() }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request.withAppIdentity())

        if let http = response as? HTTPURLResponse {
            debugLog("[Chat] listChats status:", http.statusCode)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "Unable to load chats."
            throw NSError(
                domain: "ChatManager",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        return try JSONDecoder().decode(ListChatsResponse.self, from: data)
    }
    private struct ListChatsResponse: Decodable {
        let chats: [ChatSummary]
        let more: Bool?
        let nextBefore: String?

        enum CodingKeys: String, CodingKey {
            case chats
            case more
            case nextBefore = "next_before"
        }
    }

    func loadChat(threadID: String) async {
        do {
            let loaded = try await fetchChat(threadID: threadID)
            pollingTask?.cancel()
            storedThreadID = threadID
            messages = loaded.messages
            conversationName = loaded.name
            inputText = ""
            pendingScrollTarget = messages.last?.id
            lastUserMessageID = messages.last(where: { $0.sender == .user })?.id
            clearAnswerExtras()
            resetStatusState()
        } catch {
            debugLog("[Chat] loadChat failed:", error)
        }
    }
    func deleteChat(threadID: String) async {
        do {
            try await performDeleteChat(threadID: threadID)
            chats.removeAll { $0.id == threadID }

            if storedThreadID == threadID {
                newChat()
            }
        } catch {
            debugLog("[Chat] deleteChat failed:", error)
        }
    }

    private func performDeleteChat(threadID: String) async throws {
        var components = URLComponents(string: "\(baseURL)/delete_chat/")!
        var queryItems = [URLQueryItem(name: "thread_id", value: threadID)]

        if let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty {
            queryItems.append(URLQueryItem(name: "chat_user_id", value: chatUserID))
        }

        components.queryItems = queryItems
        let url = components.url!

        debugLog("[Chat] deleteChat URL:", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request.withAppIdentity())

        if let http = response as? HTTPURLResponse {
            debugLog("[Chat] deleteChat status:", http.statusCode)
        }
        if let raw = String(data: data, encoding: .utf8) {
            debugLog("[Chat] deleteChat raw response:", raw)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "Unable to delete chat."
            throw NSError(
                domain: "ChatManager",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
    private func fetchChat(threadID: String) async throws -> LoadedChat {
        var components = URLComponents(string: "\(baseURL)/load_chat/")!
        var queryItems = [URLQueryItem(name: "thread_id", value: threadID)]

        if let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty {
            queryItems.append(URLQueryItem(name: "chat_user_id", value: chatUserID))
        }

        components.queryItems = queryItems
        let url = components.url!

        debugLog("[Chat] loadChat URL:", url.absoluteString)

        let (data, response) = try await URLSession.shared.data(for: .app(url))

        if let http = response as? HTTPURLResponse {
            debugLog("[Chat] loadChat status:", http.statusCode)
        }
        if let raw = String(data: data, encoding: .utf8) {
            debugLog("[Chat] loadChat raw response:", raw)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "Unable to load chat."
            throw NSError(
                domain: "ChatManager",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        return try parseLoadedChat(from: data)
    }

    private struct LoadedChat {
        let name: String?
        let messages: [ChatMessage]
    }

    private func parseLoadedChat(from data: Data) throws -> LoadedChat {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dict = json as? [String: Any] else {
            throw NSError(
                domain: "ChatManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Loaded chat was not a JSON object."]
            )
        }

        let name = dict["name"] as? String
        let messageObjects = dict["messages"] as? [[String: Any]] ?? []
        let loadedMessages = messageObjects.flatMap { parseLoadedMessages(from: $0) }
        return LoadedChat(name: name, messages: loadedMessages)
    }
    private func parseLoadedMessages(from dict: [String: Any]) -> [ChatMessage] {
        let roleRaw = (dict["role"] as? String)?.lowercased() ?? "assistant"

        let sender: ChatSender
        switch roleRaw {
        case "user":
            sender = .user
        case "system":
            sender = .system
        default:
            sender = .assistant
        }

        let content = (dict["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { return [] }

        guard sender == .assistant else {
            return [
                ChatMessage(
                    sender: sender,
                    text: content,
                    payloadType: nil,
                    displayBlocks: buildDisplayBlocks(
                        from: content,
                        enableInlineMarkdown: false,
                        preserveStructure: false
                    )
                )
            ]
        }

        let segments = splitAssistantContentIntoSegments(content)
        return segments.compactMap { segment in
            switch segment {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return ChatMessage(
                    sender: .assistant,
                    text: trimmed,
                    payloadType: nil,
                    displayBlocks: buildDisplayBlocks(
                        from: trimmed,
                        enableInlineMarkdown: true,
                        preserveStructure: true
                    )
                )
            case .chart(let json):
                let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return ChatMessage(
                    sender: .assistant,
                    text: "",
                    payloadType: .chart,
                    chartSpecJSON: normalizeLoadedChartJSON(trimmed)
                )
            }
        }
    }

    private enum LoadedAssistantSegment {
        case text(String)
        case chart(String)
    }

    private func splitAssistantContentIntoSegments(_ content: String) -> [LoadedAssistantSegment] {
        let marker = "```chart"
        var remaining = content[...]
        var segments: [LoadedAssistantSegment] = []

        while let startRange = remaining.range(of: marker) {
            let before = String(remaining[..<startRange.lowerBound])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(before))
            }

            let chartStart = startRange.upperBound
            let afterMarker = remaining[chartStart...]

            guard let endRange = afterMarker.range(of: "```") else {
                let fallback = String(remaining[startRange.lowerBound...])
                if !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(fallback))
                }
                remaining = ""[...]
                break
            }

            let chartBody = String(afterMarker[..<endRange.lowerBound])
            if !chartBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.chart(chartBody))
            }

            remaining = afterMarker[endRange.upperBound...]
        }

        let tail = String(remaining)
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.text(tail))
        }

        return segments
    }
    func newChat() {
        pollingTask?.cancel()
        storedThreadID = Self.newThreadID()
        messages = []
        inputText = ""
        conversationName = nil
        pendingScrollTarget = nil
        lastUserMessageID = nil
        clearAnswerExtras()
        resetStatusState()
    }

    /// Streaming preview, offer and follow-up state belong to one answer.
    private func clearAnswerExtras() {
        streamingPreamble = ""
        streamingTokens = ""
        repeatOffer = nil
        lastAnswerHadData = false
        lastAnswerText = nil
        followUpChip = nil
        repeatOfferStatus = nil
        isAcceptingRepeatOffer = false
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

    /// Runs a recipe the way the web does: a fresh chat whose question reads
    /// "Recipe · place" while the built prompt goes to the server, which
    /// links the run to the chat through `recipeRunID`.
    func runRecipe(prompt: String, display: String, planFirst: Bool?, recipeRunID: Int?) async {
        guard !isSending else { return }
        newChat()
        let userMessage = ChatMessage(
            sender: .user,
            text: display,
            displayBlocks: buildDisplayBlocks(from: display, enableInlineMarkdown: false, preserveStructure: false)
        )
        messages.append(userMessage)
        lastUserMessageID = userMessage.id
        await send(prompt: prompt, display: display, planFirst: planFirst, recipeRunID: recipeRunID)
    }

    func send(prompt: String, display: String? = nil, planFirst: Bool? = nil, recipeRunID: Int? = nil) async {
        isSending = true
        clearAnswerExtras()
        statusMessages = [
            ChatMessage(
                sender: .system,
                text: "Analyzing your question",
                payloadType: .status,
                isEphemeral: true
            )
        ]
        statusText = "Analyzing your question"
        let sendingThreadID = threadID
        lastPrompt = prompt

        // The stream is the web's path: the answer arrives as it's written,
        // and only it carries the repeat offer. Fall back to the older
        // request-and-poll path only when the stream itself fails, never
        // because of what an answer contained, so a question never runs twice
        // over a display problem.
        do {
            let uniqueID = try await generateUniqueID()
            let result = try await streamQuery(
                prompt: prompt, uniqueID: uniqueID, threadID: sendingThreadID,
                display: display, planFirst: planFirst, recipeRunID: recipeRunID
            )
            guard sendingThreadID == threadID else {
                abandonAnswer()  // the member started a new chat meanwhile
                return
            }
            finishStreamedAnswer(result, answerID: "response" + uniqueID)
            return
        } catch let unreadable as StreamResultUnreadable {
            // The question already ran; re-asking would run it twice.
            guard sendingThreadID == threadID else { abandonAnswer(); return }
            showSendError(unreadable.underlying)
            return
        } catch let failure as StreamFailure {
            debugLog("[Chat] stream failed, falling back:", failure.reason)
        } catch {
            debugLog("[Chat] stream failed, falling back:", error)
        }
        guard sendingThreadID == threadID else { abandonAnswer(); return }
        streamingPreamble = ""
        streamingTokens = ""
        await sendByPolling(prompt: prompt)
    }

    /// Drops an answer that finished after the member moved to another chat.
    private func abandonAnswer() {
        streamingPreamble = ""
        streamingTokens = ""
        resetStatusState()
        isSending = false
    }

    /// Adds the error bubble the polled path has always shown.
    private func showSendError(_ error: Error) {
        let messageText: String
        if let decodingError = error as? DecodingError {
            messageText = "Something went wrong reading the response from Spark.\n\n\(describeDecodingError(decodingError))"
        } else {
            messageText = "Something went wrong sending your message.\n\n\(error.localizedDescription)"
        }
        streamingPreamble = ""
        streamingTokens = ""
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

    private func finishStreamedAnswer(_ result: StreamResultPayload, answerID: String) {
        streamingPreamble = ""
        streamingTokens = ""
        if let name = result.conversationName, !name.isEmpty {
            conversationName = name
        }
        removeEphemeralMessages()
        appendBackendMessages(result.messages, sender: .assistant, answerID: answerID)
        autoPin(result.messages)
        repeatOffer = result.repeatOffer
        lastAnswerHadData = result.hadData
        lastAnswerText = result.responseText
        upsertCurrentChatSummary()
        resetStatusState()
        isSending = false
        pendingScrollTarget = lastUserMessageID

        let chartCount = result.messages.filter { $0.type == "chart" }.count
        let threadAtAnswer = threadID
        Task { [weak self] in
            await self?.loadFollowUpChip(chartCount: chartCount, threadAtAnswer: threadAtAnswer)
        }
    }

    // MARK: - Pins

    /// Pins what an answer made, as the web does the moment it shows it:
    /// each chart (its spec), each post/email/script (its text), a one-sheet
    /// (its spec JSON) and each source (url and type). The web's report,
    /// slides and files pages are built from these pins, so without them a
    /// chat asked in the app opened empty there.
    private func autoPin(_ backendMessages: [BackendChatMessage]) {
        let thread = threadID
        let chatLabel = (conversationName?.isEmpty == false ? conversationName : nil) ?? "Untitled"
        var pending: [(type: String, label: String, content: Any)] = []
        for item in backendMessages {
            switch item.type {
            case "chart":
                for json in chartSpecJSONs(from: item.body) {
                    guard let data = json.data(using: .utf8),
                          let spec = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                    pending.append(("chart", (spec["title"] as? String) ?? "Chart", spec))
                }
            case "response":
                let text = item.body.textValue
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\r\n", with: "\n")
                let (withoutSources, sources) = extractSourcesBlock(from: text)
                let (_, cards) = extractContentCards(from: withoutSources)
                for card in cards {
                    pending.append((card.kind, chatLabel, card.content))
                }
                for source in sources {
                    pending.append(("source", source.title, ["url": source.href, "link_type": source.linkType]))
                }
            default:
                continue
            }
        }
        guard !pending.isEmpty else { return }
        // One save at a time: /save_pin/ rewrites the whole pin file, so two
        // in flight can each drop the other's pin.
        pinQueue = Task { [previous = pinQueue] in
            await previous?.value
            for pin in pending {
                await Self.savePin(threadID: thread, type: pin.type, label: pin.label, content: pin.content)
            }
        }
    }
    private var pinQueue: Task<Void, Never>?

    private static func savePin(threadID: String, type: String, label: String, content: Any) async {
        var components = URLComponents(string: "\(serverBaseURL)/save_pin/")!
        if let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty {
            components.queryItems = [URLQueryItem(name: "chat_user_id", value: chatUserID)]
        }
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["thread_id": threadID, "type": type, "label": String(label.prefix(200)), "content": content]
        guard JSONSerialization.isValidJSONObject(body) else { return }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request.withAppIdentity())
    }

    /// The open chat's pinboard.
    func loadPins() async -> [SparkPin] {
        await Self.fetchPins(threadID: threadID)
    }

    private static func fetchPins(threadID: String) async -> [SparkPin] {
        var components = URLComponents(string: "\(serverBaseURL)/load_pins/")!
        var items = [URLQueryItem(name: "thread_id", value: threadID)]
        if let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty {
            items.append(URLQueryItem(name: "chat_user_id", value: chatUserID))
        }
        components.queryItems = items
        guard let url = components.url,
              let reply = try? await URLSession.shared.data(for: .app(url)),
              let json = (try? JSONSerialization.jsonObject(with: reply.0)) as? [String: Any],
              let raw = json["pins"] as? [[String: Any]] else { return [] }
        return raw.compactMap(SparkPin.init(json:))
    }

    // MARK: - Pin uses

    /// What was done with a pin, in the web's step words. The web pinboard
    /// shows "Copied" or "Downloaded" on the pin instead of "Not used yet".
    enum PinUse: String {
        case copied
        case exported
    }

    /// Which of the open chat's pins a use belongs to.
    enum PinMatch {
        case id(String)
        /// A post, email or script, by its text.
        case text(String)
        case chartTitle(String)
        case allCharts
    }

    /// Records a use on the open chat's pin. Static because the chat's cards
    /// don't hold the chat manager; the open chat is the stored thread id,
    /// as EventTracker reads it. Quiet: the app logs its own spark_copy and
    /// spark_export events, so the server doesn't log a second one.
    static func recordPinUse(_ use: PinUse, _ match: PinMatch) {
        guard let thread = UserDefaults.standard.string(forKey: "currentChatThreadID"), !thread.isEmpty else { return }
        Task {
            var ids = matchingPinIDs(match, in: [])
            if ids.isEmpty {
                ids = matchingPinIDs(match, in: await fetchPins(threadID: thread))
            }
            if ids.isEmpty {
                // A fresh answer's pins can still be saving.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                ids = matchingPinIDs(match, in: await fetchPins(threadID: thread))
            }
            for id in ids {
                await postStep(threadID: thread, stepID: "ns:\(use.rawValue):\(id)")
            }
        }
    }

    private static func matchingPinIDs(_ match: PinMatch, in pins: [SparkPin]) -> [String] {
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch match {
        case .id(let id):
            return [id]
        case .text(let text):
            let wanted = clean(text)
            return pins.filter { pin in clean(pin.text ?? "") == wanted && !wanted.isEmpty }.map { $0.id }
        case .chartTitle(let title):
            let wanted = clean(title)
            return pins.filter { pin in pin.type == "chart" && clean(pin.label) == wanted && !wanted.isEmpty }.map { $0.id }
        case .allCharts:
            return pins.filter { $0.type == "chart" }.map { $0.id }
        }
    }

    private static func postStep(threadID: String, stepID: String) async {
        var components = URLComponents(string: "\(serverBaseURL)/save_step/")!
        if let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty {
            components.queryItems = [URLQueryItem(name: "chat_user_id", value: chatUserID)]
        }
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["thread_id": threadID, "step_id": stepID, "quiet": true]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request.withAppIdentity())
    }

    /// A one-time link that opens `path` on the web signed in as this member,
    /// for the web's report and slides editors.
    func webLink(path: String) async throws -> URL {
        try await SparkLibraryService.webLink(path: path)
    }

    // MARK: - After an answer

    /// The web's one chip under an answer. A repeat offer takes its place.
    /// Charted answers get a caption prompt (the web's slide-deck chip opens
    /// a web-only page, so the app leaves it out); other data answers ask
    /// /suggest_followups/ and show its first suggestion.
    private func loadFollowUpChip(chartCount: Int, threadAtAnswer: String) async {
        guard repeatOffer == nil, lastAnswerHadData,
              let answer = lastAnswerText, !answer.isEmpty else { return }
        if chartCount > 0 {
            followUpChip = "Write a caption for this chart"
            return
        }
        guard let url = URL(string: "\(baseURL)/suggest_followups/") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "response_text": String(answer.prefix(800)),
            "has_chart": false,
        ])
        guard let reply = try? await URLSession.shared.data(for: request.withAppIdentity()),
              let json = (try? JSONSerialization.jsonObject(with: reply.0)) as? [String: Any],
              let chips = json["chips"] as? [String],
              let first = chips.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return }
        // Drop a suggestion that arrives after the member moved on.
        guard threadAtAnswer == threadID, !isSending, lastAnswerText == answer else { return }
        followUpChip = first
    }

    /// Sends the chip as the next question.
    func sendFollowUpChip() async {
        guard let chip = followUpChip, !isSending else { return }
        followUpChip = nil
        inputText = chip
        await sendCurrentMessage()
    }

    /// "Make this automatic": saves the last question as a recipe, then
    /// schedules it, the same two calls the web makes. Needs the member's
    /// Bearer token; the server refuses the typeable chat_user_id here.
    func acceptRepeatOffer(cadence: String) async {
        guard let offer = repeatOffer, let prompt = lastPrompt, !isAcceptingRepeatOffer else { return }
        isAcceptingRepeatOffer = true
        defer { isAcceptingRepeatOffer = false }
        let thread = threadID

        func post(_ path: String, _ body: [String: Any]) async -> [String: Any]? {
            guard let url = URL(string: "\(baseURL)\(path)") else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            guard let reply = try? await URLSession.shared.data(for: request.withAppIdentity()) else { return nil }
            let json = (try? JSONSerialization.jsonObject(with: reply.0)) as? [String: Any]
            if let http = reply.1 as? HTTPURLResponse, http.statusCode == 401 {
                return ["ok": false, "error": "not_logged_in"]
            }
            return json
        }

        let saved = await post("/recipes/save/", ["prompt": prompt, "thread_id": thread])
        guard let recipe = saved?["recipe"] as? [String: Any], let recipeID = recipe["id"] as? String else {
            repeatOfferStatus = (saved?["error"] as? String) == "not_logged_in"
                ? "Sign out and back in to turn this on."
                : "Couldn't set that up. Try again in a minute."
            return
        }
        let scheduled = await post("/schedules/save/", [
            "recipe_id": recipeID,
            "cadence": cadence,
            "geo_label": offer.place,
            "thread_id": thread,
        ])
        guard (scheduled?["ok"] as? Bool) == true else {
            repeatOfferStatus = "Couldn't set that up. Try again in a minute."
            return
        }
        repeatOffer = nil
        repeatOfferStatus = "Done. Spark will email your \(offer.place) \(offer.kind) \(cadence == "weekly" ? "every week" : "every month")."
    }

    func dismissRepeatOffer() {
        repeatOffer = nil
    }

    /// Thumbs up or down on an answer. Posts where the web does
    /// (/submit_feedback_dev/); the server files it against the thread.
    func sendFeedback(answerID: String, positive: Bool, note: String) async {
        guard let url = URL(string: "\(baseURL)/submit_feedback_dev/") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "message_id": answerID,
            "thread_id": threadID,
            "feedback_type": positive ? "thumbs-up" : "thumbs-down",
            "additional_feedback": note,
        ])
        _ = try? await URLSession.shared.data(for: request.withAppIdentity())
    }

    /// Why a stream ended without an answer. The polled path takes over.
    private struct StreamFailure: Error {
        let reason: String
    }

    /// The stream delivered its result but the app couldn't read it.
    private struct StreamResultUnreadable: Error {
        let underlying: Error
    }

    /// POSTs the question to /stream_query/ and reads its server-sent events
    /// until the `result` event, updating the status panel and the live
    /// preview as they arrive. Frames are single `data: {json}` lines with a
    /// `kind` field; there are no `event:` lines and no done marker.
    private func streamQuery(
        prompt: String,
        uniqueID: String,
        threadID: String,
        display: String? = nil,
        planFirst: Bool? = nil,
        recipeRunID: Int? = nil
    ) async throws -> StreamResultPayload {
        var components = URLComponents(string: "\(baseURL)/stream_query/")!
        // The server reads identity from the query string or the Bearer
        // header, never from the JSON body.
        if let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty {
            components.queryItems = [URLQueryItem(name: "chat_user_id", value: chatUserID)]
        }
        guard let url = components.url else { throw StreamFailure(reason: "bad URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // The server gives up after 90 seconds without an event; wait past that.
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "prompt": prompt,
            "thread_id": threadID,
            "unique_id": uniqueID,
            // A recipe says whether to plan first; a typed question lets the
            // server decide.
            "plan_first": planFirst.map { $0 as Any } ?? "auto",
        ]
        // The label saved as the member's message instead of the built prompt.
        if let display, !display.isEmpty { body["display"] = display }
        if let recipeRunID { body["recipe_run_id"] = recipeRunID }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request.withAppIdentity())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw StreamFailure(reason: "HTTP \(code)")
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }  // ": open" comment, blanks
            let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = json.data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let kind = event["kind"] as? String else { continue }

            switch kind {
            case "status":
                guard let body = event["body"] as? String, !body.isEmpty else { continue }
                appendStreamStatus(body, pct: (event["pct"] as? NSNumber)?.doubleValue)
            case "preamble":
                streamingPreamble += event["text"] as? String ?? ""
            case "token":
                streamingTokens += event["text"] as? String ?? ""
            case "reset":
                // The prose so far turned out to be a tool call.
                streamingTokens = ""
            case "charts_pending":
                let count = (event["count"] as? NSNumber)?.intValue ?? 1
                appendStreamStatus(count == 1 ? "Drawing your chart" : "Drawing \(count) charts", pct: nil)
            case "result":
                // A result that won't decode is not a stream failure: the
                // question already ran, so show an error instead of re-asking.
                do {
                    return try JSONDecoder().decode(StreamResultPayload.self, from: data)
                } catch {
                    throw StreamResultUnreadable(underlying: error)
                }
            case "error":
                throw StreamFailure(reason: event["message"] as? String ?? "stream error")
            default:
                continue  // plan_mode and anything newer
            }
        }
        throw StreamFailure(reason: "stream ended without a result")
    }

    /// Adds a stage to the status panel. The stream sends stages one at a
    /// time; the panel shows the list, like the polled path's check_status.
    private func appendStreamStatus(_ text: String, pct: Double?) {
        var current = statusMessages
        // The placeholder shown before the first real stage.
        if current.count == 1, current.first?.text == "Analyzing your question" {
            current = []
        }
        current.append(
            ChatMessage(
                sender: .system,
                text: text,
                payloadType: .status,
                isEphemeral: true,
                displayBlocks: buildDisplayBlocks(from: text, enableInlineMarkdown: false, preserveStructure: false),
                progressPct: pct ?? current.last?.progressPct
            )
        )
        statusMessages = current
        statusText = text
    }

    /// The older path: handle_user_query, then execute_sql while polling
    /// check_status. Kept as the fallback for a failed stream.
    private func sendByPolling(prompt: String) async {
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
                appendBackendMessages(final.messages, sender: .assistant, answerID: "response" + uniqueID)
                autoPin(final.messages)
            } else {
                removeEphemeralMessages()
            }
            upsertCurrentChatSummary()
            resetStatusState()
            isSending = false
            pendingScrollTarget = lastUserMessageID
        } catch {
            debugLog("[Chat] send(prompt:) failed:", error)
            showSendError(error)
        }
    }
    private func upsertCurrentChatSummary() {
        let now = isoTimestampNow()
        let currentThreadID = threadID
        let trimmedName = conversationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmedName?.isEmpty == false) ? trimmedName! : "Untitled"

        if let index = chats.firstIndex(where: { $0.id == currentThreadID }) {
            let existing = chats[index]
            chats.remove(at: index)
            chats.insert(
                ChatSummary(
                    threadID: existing.id,
                    name: title,
                    created: existing.created ?? now,
                    updated: now
                ),
                at: 0
            )
        } else {
            chats.insert(
                ChatSummary(
                    threadID: currentThreadID,
                    name: title,
                    created: now,
                    updated: now
                ),
                at: 0
            )
        }
    }

    private func isoTimestampNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
    private func generateUniqueID() async throws -> String {
        let url = URL(string: "\(baseURL)/generate_unique_id")!
        let (data, _) = try await URLSession.shared.data(for: .app(url))
        let decoded = try JSONDecoder().decode(GenerateUniqueIDResponse.self, from: data)
        return decoded.uniqueID
    }

    private func handleUserQuery(
        prompt: String,
        uniqueID: String,
        threadID: String
    ) async throws -> HandleUserQueryResponse {
        var components = URLComponents(string: "\(baseURL)/handle_user_query")!
        var queryItems = [
            URLQueryItem(name: "prompt", value: prompt),
            URLQueryItem(name: "unique_id", value: uniqueID),
            URLQueryItem(name: "thread_id", value: threadID)
        ]

        if let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty {
            queryItems.append(URLQueryItem(name: "chat_user_id", value: chatUserID))
        }

        components.queryItems = queryItems
        let url = components.url!
        debugLog("[Chat] handleUserQuery URL:", url.absoluteString)

        let (data, response) = try await URLSession.shared.data(for: .app(url))

        if let http = response as? HTTPURLResponse {
            debugLog("[Chat] handleUserQuery status:", http.statusCode)
        }
        if let raw = String(data: data, encoding: .utf8) {
            debugLog("[Chat] handleUserQuery raw response:", raw)
        }

        return try JSONDecoder().decode(HandleUserQueryResponse.self, from: data)
    }

    private func executeSQL(
        filename: String,
        uniqueID: String,
        threadID: String
    ) async throws -> ExecuteSQLResponse {
        var components = URLComponents(string: "\(baseURL)/execute_sql")!
        var queryItems = [
            URLQueryItem(name: "filename", value: filename),
            URLQueryItem(name: "unique_id", value: uniqueID),
            URLQueryItem(name: "thread_id", value: threadID)
        ]

        if let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty {
            queryItems.append(URLQueryItem(name: "chat_user_id", value: chatUserID))
        }

        components.queryItems = queryItems
        let url = components.url!
        debugLog("[Chat] executeSQL URL:", url.absoluteString)

        let (data, response) = try await URLSession.shared.data(for: .app(url))

        if let http = response as? HTTPURLResponse {
            debugLog("[Chat] executeSQL status:", http.statusCode)
        }
        if let raw = String(data: data, encoding: .utf8) {
            debugLog("[Chat] executeSQL raw response:", raw)
        }

        return try JSONDecoder().decode(ExecuteSQLResponse.self, from: data)
    }

    private func checkStatus(uniqueID: String) async throws -> CheckStatusResponse {
        var components = URLComponents(string: "\(baseURL)/check_status")!
        components.queryItems = [URLQueryItem(name: "unique_id", value: uniqueID)]
        let (data, _) = try await URLSession.shared.data(for: .app(components.url!))
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
        sender: ChatSender,
        answerID: String? = nil
    ) {
        for item in backendMessages {
            let payload = ChatPayloadType(rawValue: item.type)
            let text = item.body.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            switch payload {
            case .status, .success, .hidden:
                continue
            case .chart:
                for spec in chartSpecJSONs(from: item.body) {
                    messages.append(
                        ChatMessage(
                            sender: .assistant,
                            text: "",
                            payloadType: payload,
                            chartSpecJSON: spec
                        )
                    )
                }
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
                        ),
                        // Only the answer prose takes feedback, as on the web.
                        answerID: item.type == "response" ? answerID : nil
                    )
                )
            }
        }
    }

    /// One JSON string per chart. An answer with several charts sends a list
    /// of specs as the body; read whole, the list decoded as no chart at all
    /// and showed "Chart unavailable."
    private func chartSpecJSONs(from body: FlexibleBody) -> [String] {
        func serialize(_ object: Any) -> String? {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        switch body {
        case .array(let items):
            return items.compactMap { serialize($0.value) }
        case .string(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("["),
               let data = trimmed.data(using: .utf8),
               let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
                return list.compactMap(serialize)
            }
            return trimmed.isEmpty ? [] : [trimmed]
        default:
            let text = body.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [text]
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
                    displayBlocks: buildDisplayBlocks(from: text, enableInlineMarkdown: false, preserveStructure: false),
                    progressPct: item.pct
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

    private struct ParsedSourceLink: Hashable {
        let title: String
        let href: String
        let linkType: String
        let note: String?
    }

    /// Fenced blocks this client knows how to render. `chart` is included
    /// because a separate path pulls it out before display.
    private static let renderableFences: Set<String> = ["chart", "post", "email", "script", "sources"]

    /// Drop fenced blocks meant for other clients — one-sheets, insight
    /// payloads, download descriptors, pin lists. Without this they print as
    /// raw JSON in the transcript, and every new block type the server learns
    /// becomes a visual bug here. Untagged ``` blocks are left alone; those are
    /// ordinary code fences.
    private func stripUnknownFences(from text: String) -> String {
        let pattern = #"```([A-Za-z][A-Za-z0-9_-]*)[ \t]*\n[\s\S]*?```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        // Reverse order so each removal leaves the earlier ranges valid.
        for match in matches.reversed() where match.numberOfRanges >= 2 {
            let tag = nsText.substring(with: match.range(at: 1)).lowercased()
            if Self.renderableFences.contains(tag) { continue }
            mutable.replaceCharacters(in: match.range(at: 0), with: "")
        }
        return (mutable as String).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pulls out the blocks that become SparkCards. `pinlist` is claimed and
    /// dropped: it lists pins for the web pinboard, which the app doesn't have.
    private func extractSparkCards(from text: String) -> (cleanedText: String, cards: [SparkCard]) {
        let pattern = #"```(insights|file|download|drawarea|pinlist)\s*\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return (text, [])
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range)
        if matches.isEmpty { return (text, []) }

        var cards: [SparkCard] = []
        for match in matches where match.numberOfRanges >= 3 {
            let tag = nsText.substring(with: match.range(at: 1)).lowercased()
            let body = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let card = sparkCard(tag: tag, json: json) {
                cards.append(card)
            }
        }
        let cleaned = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, cards)
    }

    private func sparkCard(tag: String, json: Any) -> SparkCard? {
        func string(_ dict: [String: Any], _ key: String) -> String? {
            let value = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        }
        switch tag {
        case "insights":
            let items = (json as? [[String: Any]] ?? []).compactMap { item -> SparkInsight? in
                guard let headline = string(item, "headline") ?? string(item, "title") else { return nil }
                return SparkInsight(
                    headline: headline,
                    geo: string(item, "geo"),
                    direction: string(item, "direction"),
                    change: string(item, "change"),
                    valueFmt: string(item, "value_fmt"),
                    reportDate: string(item, "report_date")
                )
            }
            return items.isEmpty ? nil : .insights(items)
        case "file":
            guard let dict = json as? [String: Any],
                  let raw = string(dict, "url") else { return nil }
            let url = normalizedInternalURLString(from: raw)
            // Same rule as the web: only the Hub itself or its file storage.
            guard let host = URL(string: url)?.host,
                  host == AppIdentity.hubHost || host.hasSuffix(".digitaloceanspaces.com") else { return nil }
            return .file(SparkFileLink(
                url: url,
                name: string(dict, "name") ?? "Your file",
                description: string(dict, "description")
            ))
        case "download":
            guard let dict = json as? [String: Any] else { return nil }
            return .download(
                label: string(dict, "label") ?? "Your download",
                webURL: "\(baseURL)/chat/\(threadID)/"
            )
        case "drawarea":
            guard let dict = json as? [String: Any] else { return nil }
            return .drawArea(name: string(dict, "name") ?? "this area", webURL: "\(baseURL)/area/")
        default:
            return nil  // pinlist
        }
    }

    private func extractContentCards(from text: String) -> (cleanedText: String, cards: [ContentCardData]) {
        let pattern = #"```(post|email|script|onesheet)\s*\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return (text, [])
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range)
        if matches.isEmpty { return (text, []) }

        var cards: [ContentCardData] = []
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let kindRange = Range(match.range(at: 1), in: text),
                  let contentRange = Range(match.range(at: 2), in: text) else { continue }
            let kind = String(text[kindRange]).lowercased()
            let rawContent = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            // A one-sheet's body is the spec JSON the server takes back verbatim
            // for the PDF — running the markdown scrub over it could corrupt it.
            let content = kind == "onesheet"
                ? rawContent
                : rawContent
                    .replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: #"\*(.+?)\*"#, with: "$1", options: .regularExpression)
            cards.append(ContentCardData(kind: kind, content: content))
        }
        let cleaned = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, cards)
    }

    private func extractSourcesBlock(from text: String) -> (cleanedText: String, links: [ParsedSourceLink]) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let pattern = #"```sources\s*\n([\s\S]*?)```\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }

        let nsText = normalized as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: normalized, range: range), match.numberOfRanges >= 2,
              let fullRange = Range(match.range(at: 0), in: normalized),
              let jsonRange = Range(match.range(at: 1), in: normalized) else {
            return (normalized, [])
        }

        let jsonString = String(normalized[jsonRange])
        let cleaned = String(normalized[..<fullRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8),
              let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return (normalized, [])
        }

        let links: [ParsedSourceLink] = rawArray.compactMap { item in
            let linkType = (item["link_type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "source"
            let reportURL = (item["report_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let vizURL = (item["viz_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let legacyURL = (item["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let href: String?
            switch linkType.lowercased() {
            case "report":
                href = reportURL ?? vizURL ?? legacyURL
            case "chart":
                href = vizURL ?? reportURL ?? legacyURL
            default:
                href = vizURL ?? reportURL ?? legacyURL
            }

            guard let resolvedHref = href, !resolvedHref.isEmpty else { return nil }

            let rawTitle = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = (item["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            return ParsedSourceLink(
                title: (rawTitle?.isEmpty == false) ? rawTitle! : resolvedHref,
                href: normalizedInternalURLString(from: resolvedHref),
                linkType: linkType,
                note: (note?.isEmpty == false) ? note : nil
            )
        }

        return (cleaned, links)
    }

    private func chatRelatedLinks(from sourceLinks: [ParsedSourceLink]) -> [ChatRelatedLink] {
        sourceLinks.map { source in
            let trimmedType = source.linkType.trimmingCharacters(in: .whitespacesAndNewlines)
            let typePrefix = trimmedType.isEmpty ? "" : "[\(trimmedType.uppercased())] "
            let noteSuffix = (source.note?.isEmpty == false) ? " • \(source.note!)" : ""
            return ChatRelatedLink(
                title: "\(typePrefix)\(source.title)\(noteSuffix)",
                urlString: source.href
            )
        }
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

        let (textWithoutSources, sourceLinks) = extractSourcesBlock(from: normalizedText)
        let (textWithoutSparkCards, sparkCards) = extractSparkCards(from: textWithoutSources)
        let (textWithoutCards, contentCards) = extractContentCards(from: textWithoutSparkCards)
        // After the blocks this client renders have been claimed, anything still
        // fenced belongs to another client and shouldn't be shown as text.
        let textCleaned = stripUnknownFences(from: textWithoutCards)
        let relatedSourceLinks = chatRelatedLinks(from: sourceLinks)
        let expandedText = enableInlineMarkdown ? expandMarkdownLinksToAbsoluteURLs(in: textCleaned) : textCleaned

        guard preserveStructure else {
            let inlineLinks = extractMarkdownLinks(from: expandedText).map {
                ChatRelatedLink(
                    title: $0.title,
                    urlString: $0.href
                )
            }
            return [
                ChatDisplayBlock(
                    kind: .paragraph,
                    plainText: expandedText,
                    attributedText: makeInlineMarkdown(expandedText, enabled: enableInlineMarkdown),
                    tableData: nil,
                    relatedLinks: inlineLinks + relatedSourceLinks
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
                let relatedLinks = extractMarkdownLinks(from: paragraph).map {
                    ChatRelatedLink(
                        title: $0.title,
                        urlString: $0.href
                    )
                }
                result.append(
                    ChatDisplayBlock(
                        kind: .paragraph,
                        plainText: paragraph,
                        attributedText: makeInlineMarkdown(paragraph, enabled: enableInlineMarkdown),
                        tableData: nil,
                        relatedLinks: relatedLinks
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
            let inlineLinks = extractMarkdownLinks(from: expandedText).map {
                ChatRelatedLink(
                    title: $0.title,
                    urlString: $0.href
                )
            }
            return [
                ChatDisplayBlock(
                    kind: .paragraph,
                    plainText: expandedText,
                    attributedText: makeInlineMarkdown(expandedText, enabled: enableInlineMarkdown),
                    tableData: nil,
                    relatedLinks: inlineLinks + relatedSourceLinks
                )
            ]
        }

        if !relatedSourceLinks.isEmpty {
            if let lastParagraphIndex = result.lastIndex(where: { $0.kind == .paragraph || $0.kind == .bullet }) {
                let block = result[lastParagraphIndex]
                result[lastParagraphIndex] = ChatDisplayBlock(
                    kind: block.kind,
                    plainText: block.plainText,
                    attributedText: block.attributedText,
                    tableData: block.tableData,
                    relatedLinks: (block.relatedLinks ?? []) + relatedSourceLinks
                )
            } else {
                result.append(
                    ChatDisplayBlock(
                        kind: .paragraph,
                        plainText: "",
                        attributedText: nil,
                        tableData: nil,
                        relatedLinks: relatedSourceLinks
                    )
                )
            }
        }

        for card in contentCards {
            result.append(ChatDisplayBlock(
                kind: .contentCard,
                plainText: card.content,
                attributedText: nil,
                tableData: nil,
                relatedLinks: nil,
                contentCardData: card
            ))
        }

        for card in sparkCards {
            result.append(ChatDisplayBlock(
                kind: .sparkCard,
                plainText: "",
                attributedText: nil,
                tableData: nil,
                relatedLinks: nil,
                sparkCard: card
            ))
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

    private func normalizeLoadedChartJSON(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\t", with: "\t")
    }
