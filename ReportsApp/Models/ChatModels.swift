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
    case contentCard
}

struct ContentCardData: Equatable {
    let kind: String  // "post", "email", "script", "onesheet"
    let content: String  // copyable text, except onesheet where it's the spec JSON

    var heading: String {
        switch kind {
        case "post": return "Here's your post"
        case "email": return "Here's your email"
        case "script": return "Here's your script"
        case "onesheet": return "Here's your one-sheet"
        default: return "Here's your content"
        }
    }

    var systemImage: String {
        switch kind {
        case "email": return "envelope"
        case "script": return "text.alignleft"
        case "onesheet": return "doc.richtext"
        default: return "sparkles"
        }
    }

    /// Copy-ready plain text: markdown links flattened to visible URLs.
    /// A social composer can't render an anchor, so the URL has to survive as
    /// characters or it's silently lost on paste. Mirrors the web's _flattenMd.
    var copyPlainText: String {
        var text = content
        if let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^\s)]+)\)"#) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
                let label = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let url = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                let flat = label == url ? url : "\(label) (\(url))"
                text = (text as NSString).replacingCharacters(in: match.range(at: 0), with: flat)
            }
        }
        return text
    }

    /// Rich flavor for the pasteboard — email only. Gmail/Outlook paste this as
    /// real hyperlinks. Posts deliberately stay plain: pasting an anchor into a
    /// social composer keeps the label and drops the href.
    var copyHTML: String? {
        guard kind == "email" else { return nil }
        var html = content
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        if let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^\s)]+)\)"#) {
            let ns = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
                let label = ns.substring(with: match.range(at: 1))
                let url = ns.substring(with: match.range(at: 2))
                html = (html as NSString).replacingCharacters(
                    in: match.range(at: 0),
                    with: "<a href=\"\(url)\">\(label)</a>"
                )
            }
        }
        html = html.replacingOccurrences(of: "\n", with: "<br>")
        return "<div style=\"font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.6;\">\(html)</div>"
    }
}

/// The parsed body of a ```onesheet block. The server's /onesheet/pdf/ endpoint
/// takes this same JSON back verbatim, so the card keeps the raw string for the
/// POST and this struct only drives the on-screen preview.
struct OnesheetSpec: Decodable, Equatable {
    struct Section: Decodable, Equatable {
        let heading: String?
        let bullets: [String]?
    }
    let title: String?
    let subtitle: String?
    let sections: [Section]?

    static func parse(_ json: String) -> OnesheetSpec? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OnesheetSpec.self, from: data)
    }
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
    let contentCardData: ContentCardData?

    init(
        kind: ChatDisplayBlockKind,
        plainText: String,
        attributedText: AttributedString?,
        tableData: ChatTableData?,
        relatedLinks: [ChatRelatedLink]?,
        contentCardData: ContentCardData? = nil
    ) {
        self.kind = kind
        self.plainText = plainText
        self.attributedText = attributedText
        self.tableData = tableData
        self.relatedLinks = relatedLinks
        self.contentCardData = contentCardData
    }
}

struct BackendChatMessage: Decodable {
    let type: String
    let body: FlexibleBody
    /// Progress for a status message, 0-100, sent by the server.
    /// Optional so older payloads (and any endpoint that doesn't send it) decode fine.
    let pct: Double?
    /// Monotonic sequence for status messages. The server appends stages rather
    /// than replacing, so this identifies which ones have already been shown.
    let seq: Int?
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
    /// Server-sent progress for a status message, 0-100. The status wording is
    /// dynamic now ("Looking up Median Sale Price for Hamilton County"), so the
    /// bar can't be inferred from the text any more.
    let progressPct: Double?

    init(
        sender: ChatSender,
        text: String,
        payloadType: ChatPayloadType? = nil,
        isEphemeral: Bool = false,
        chartSpecJSON: String? = nil,
        displayBlocks: [ChatDisplayBlock]? = nil,
        progressPct: Double? = nil
    ) {
        self.sender = sender
        self.text = text
        self.payloadType = payloadType
        self.isEphemeral = isEphemeral
        self.chartSpecJSON = chartSpecJSON
        self.displayBlocks = displayBlocks
        self.progressPct = progressPct
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
