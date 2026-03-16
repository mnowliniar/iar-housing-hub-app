//
//  ChatSender.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/13/26.
//


import Foundation

enum ChatSender {
    case user
    case assistant
    case system
}

enum ChatPayloadType: String, Codable {
    case status
    case guts
    case success
    case error
    case chart
    case gutslink
    case hidden
}

enum ChatDisplayBlockKind: Equatable {
    case paragraph
    case bullet
    case table
}


struct ChatTableData: Equatable {
    let headers: [String]
    let rows: [[String]]
}

struct ChatRelatedLink: Equatable {
    let title: String
    let urlString: String
}

struct ChatDisplayBlock: Identifiable, Equatable {
    let id = UUID()
    let kind: ChatDisplayBlockKind
    let plainText: String
    let attributedText: AttributedString?
    let tableData: ChatTableData?
    let relatedLinks: [ChatRelatedLink]?
}

struct BackendChatMessage: Decodable {
    let type: String
    let body: FlexibleBody
}

enum FlexibleBody: Decodable {
    case string(String)
    case object([String: AnyDecodable])
    case array([AnyDecodable])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AnyDecodable].self) {
            self = .object(value)
        } else if let value = try? container.decode([AnyDecodable].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var textValue: String {
        switch self {
        case .string(let s):
            return s
        case .object(let obj):
            if let pretty = try? JSONSerialization.data(
                withJSONObject: obj.mapValues(\.value),
                options: [.prettyPrinted]
            ),
               let str = String(data: pretty, encoding: .utf8) {
                return str
            }
            return "[Object]"
        case .array(let arr):
            let raw = arr.map(\.value)
            if let pretty = try? JSONSerialization.data(
                withJSONObject: raw,
                options: [.prettyPrinted]
            ),
               let str = String(data: pretty, encoding: .utf8) {
                return str
            }
            return "[Array]"
        case .null:
            return ""
        }
    }
}

struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let dict = try? container.decode([String: AnyDecodable].self) {
            value = dict.mapValues(\.value)
        } else if let array = try? container.decode([AnyDecodable].self) {
            value = array.map(\.value)
        } else {
            value = NSNull()
        }
    }
}

struct GenerateUniqueIDResponse: Decodable {
    let uniqueID: String

    enum CodingKeys: String, CodingKey {
        case uniqueID = "unique_id"
    }
}

struct HandleUserQueryResponse: Decodable {
    let messages: [BackendChatMessage]
    let filename: String?
    let uniqueID: String?
    let conversationName: String?

    enum CodingKeys: String, CodingKey {
        case messages
        case filename
        case uniqueID = "unique_id"
        case conversationName = "conversation_name"
    }
}

struct ExecuteSQLResponse: Decodable {
    let messages: [BackendChatMessage]
    let uniqueID: String?

    enum CodingKeys: String, CodingKey {
        case messages
        case uniqueID = "unique_id"
    }
}

struct CheckStatusResponse: Decodable {
    let messages: [BackendChatMessage]
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let sender: ChatSender
    let text: String
    let payloadType: ChatPayloadType?
    let isEphemeral: Bool
    let chartSpecJSON: String?
    let displayBlocks: [ChatDisplayBlock]?

    init(
        sender: ChatSender,
        text: String,
        payloadType: ChatPayloadType? = nil,
        isEphemeral: Bool = false,
        chartSpecJSON: String? = nil,
        displayBlocks: [ChatDisplayBlock]? = nil
    ) {
        self.sender = sender
        self.text = text
        self.payloadType = payloadType
        self.isEphemeral = isEphemeral
        self.chartSpecJSON = chartSpecJSON
        self.displayBlocks = displayBlocks
    }
}

struct ChatSummary: Identifiable, Decodable, Equatable {
    var id: String { threadID }

    let threadID: String
    let name: String
    let created: String?
    let updated: String?

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case name
        case created
        case updated
    }
}
