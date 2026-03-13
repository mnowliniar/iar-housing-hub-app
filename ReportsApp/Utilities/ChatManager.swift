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

    @AppStorage("currentChatThreadID") private var storedThreadID: String = ""

    private let baseURL = "https://data.indianarealtors.com"
    private var pollingTask: Task<Void, Never>?

    var threadID: String {
        if storedThreadID.isEmpty {
            storedThreadID = UUID().uuidString
        }
        return storedThreadID
    }

    func newChat() {
        pollingTask?.cancel()
        storedThreadID = UUID().uuidString
        messages = []
        inputText = ""
        conversationName = nil
        resetStatusState()
    }

    func sendCurrentMessage() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }

        inputText = ""
        messages.append(ChatMessage(sender: .user, text: prompt))
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
        } catch {
            removeEphemeralMessages()
            messages.append(
                ChatMessage(
                    sender: .system,
                    text: "Something went wrong sending your message.",
                    payloadType: .error
                )
            )
            resetStatusState()
            isSending = false
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
        let (data, _) = try await URLSession.shared.data(from: components.url!)
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
                        text: "[Chart]\n\(text)",
                        payloadType: payload
                    )
                )
            default:
                messages.append(
                    ChatMessage(
                        sender: sender,
                        text: text,
                        payloadType: payload
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
                    isEphemeral: true
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
}
