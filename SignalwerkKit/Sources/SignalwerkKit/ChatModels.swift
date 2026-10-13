import Foundation

// Chat-Zeilen, wie sie der Alert-Dienst schickt (src/lib/chat/types.ts im Dashboard).

public struct ChatEmote: Codable, Equatable, Hashable {
    public let id: String
    /// Position in Unicode-Zeichen (Codepoints), beide Enden inklusive.
    public let start: Int
    public let end: Int
    public init(id: String, start: Int, end: Int) {
        self.id = id
        self.start = start
        self.end = end
    }
}

public struct ChatReply: Codable, Equatable, Hashable {
    public let login: String
    public let name: String
    public let text: String
}

public struct ChatClear: Codable, Equatable, Hashable {
    /// "timeout", "ban" oder "chat".
    public let kind: String
    public let seconds: Int?
    public let at: Double
    public init(kind: String, seconds: Int?, at: Double) {
        self.kind = kind
        self.seconds = seconds
        self.at = at
    }
}

public struct ChatMessage: Codable, Equatable, Hashable, Identifiable {
    public let id: String
    public let at: Double
    public let userId: String
    public let login: String
    public let name: String
    public let color: String
    public let badges: [String]
    public let months: Int
    public let text: String
    public let emotes: [ChatEmote]
    public let action: Bool
    public let first: Bool
    public let returning: Bool
    public let bits: Int
    public let reply: ChatReply?
    public let shared: String?
    public var deleted: Bool
    public var cleared: ChatClear?

    public init(id: String, at: Double, userId: String, login: String, name: String, color: String, badges: [String], months: Int, text: String, emotes: [ChatEmote], action: Bool = false, first: Bool = false, returning: Bool = false, bits: Int = 0, reply: ChatReply? = nil, shared: String? = nil, deleted: Bool = false, cleared: ChatClear? = nil) {
        self.id = id
        self.at = at
        self.userId = userId
        self.login = login
        self.name = name
        self.color = color
        self.badges = badges
        self.months = months
        self.text = text
        self.emotes = emotes
        self.action = action
        self.first = first
        self.returning = returning
        self.bits = bits
        self.reply = reply
        self.shared = shared
        self.deleted = deleted
        self.cleared = cleared
    }
}

public struct ChatNotice: Codable, Equatable, Hashable {
    public let id: String
    public let at: Double
    public let type: String
    public let userId: String
    public let login: String
    public let name: String
    public let color: String
    public let badges: [String]
    public let system: String
    public let text: String
    public let emotes: [ChatEmote]

    public init(id: String, at: Double, type: String, userId: String, login: String, name: String, color: String, badges: [String], system: String, text: String, emotes: [ChatEmote]) {
        self.id = id
        self.at = at
        self.type = type
        self.userId = userId
        self.login = login
        self.name = name
        self.color = color
        self.badges = badges
        self.system = system
        self.text = text
        self.emotes = emotes
    }
}

public struct ChatSystemLine: Codable, Equatable, Hashable {
    public let id: String
    public let at: Double
    /// "timeout", "ban", "unban", "clear", "info" oder "error".
    public let tone: String
    public let text: String
    public let userId: String?
    public let login: String?

    public init(id: String, at: Double, tone: String, text: String, userId: String?, login: String?) {
        self.id = id
        self.at = at
        self.tone = tone
        self.text = text
        self.userId = userId
        self.login = login
    }
}

public enum ChatLine: Decodable, Equatable, Hashable, Identifiable {
    case message(ChatMessage)
    case notice(ChatNotice)
    case system(ChatSystemLine)

    private enum CodingKeys: String, CodingKey { case kind }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "message": self = .message(try ChatMessage(from: decoder))
        case "notice": self = .notice(try ChatNotice(from: decoder))
        case "system": self = .system(try ChatSystemLine(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unbekannte Chat-Zeile \(kind)")
        }
    }

    public var id: String {
        switch self {
        case .message(let line): return line.id
        case .notice(let line): return line.id
        case .system(let line): return line.id
        }
    }

    public var at: Double {
        switch self {
        case .message(let line): return line.at
        case .notice(let line): return line.at
        case .system(let line): return line.at
        }
    }

    public var date: Date { Date(timeIntervalSince1970: at / 1000) }

    public var userId: String? {
        switch self {
        case .message(let line): return line.userId
        case .notice(let line): return line.userId
        case .system(let line): return line.userId
        }
    }
}

/// Liest Arrays, in denen einzelne Einträge unbekannt sein dürfen (neuere Alert-Dienste).
public struct Lenient<T: Decodable>: Decodable {
    public let value: T?
    public init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

public enum ChatUpdate: Decodable, Equatable {
    case line(ChatLine)
    case delete(id: String)
    case clearUser(userId: String, clear: ChatClear)
    case clearAll(at: Double)

    private enum CodingKeys: String, CodingKey { case t, line, id, userId, clear, at }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .t)
        switch type {
        case "line": self = .line(try container.decode(ChatLine.self, forKey: .line))
        case "delete": self = .delete(id: try container.decode(String.self, forKey: .id))
        case "clear-user": self = .clearUser(userId: try container.decode(String.self, forKey: .userId), clear: try container.decode(ChatClear.self, forKey: .clear))
        case "clear-all": self = .clearAll(at: try container.decode(Double.self, forKey: .at))
        default:
            throw DecodingError.dataCorruptedError(forKey: .t, in: container, debugDescription: "Unbekannte Änderung \(type)")
        }
    }
}

public struct ChatBadgeImage: Codable, Equatable, Hashable {
    public let url: String
    public let url2: String
    public let title: String
}

public struct ChatExtraEmote: Codable, Equatable, Hashable {
    public let url: String
    public let url2: String
    /// "7tv", "bttv", "ffz" oder "twitch".
    public let provider: String
    public let channel: Bool?
    public init(url: String, url2: String, provider: String, channel: Bool?) {
        self.url = url
        self.url2 = url2
        self.provider = provider
        self.channel = channel
    }
}

public struct ChatAssets: Codable, Equatable {
    public let badges: [String: ChatBadgeImage]
    public let emotes: [String: ChatExtraEmote]
    public init(badges: [String: ChatBadgeImage] = [:], emotes: [String: ChatExtraEmote] = [:]) {
        self.badges = badges
        self.emotes = emotes
    }
    public static let empty = ChatAssets()
}

/// Antwort auf "chat-join".
public struct ChatJoinReply: Decodable {
    public let ok: Bool
    public let channel: String?
    public let connected: Bool?
    public let lines: [ChatLine]
    public let assets: ChatAssets?
    public let error: String?

    private enum CodingKeys: String, CodingKey { case ok, channel, connected, lines, assets, error }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        channel = try container.decodeIfPresent(String.self, forKey: .channel)
        connected = try container.decodeIfPresent(Bool.self, forKey: .connected)
        let raw = try container.decodeIfPresent([Lenient<ChatLine>].self, forKey: .lines) ?? []
        lines = raw.compactMap(\.value)
        assets = try? container.decodeIfPresent(ChatAssets.self, forKey: .assets)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

/// Ereignis "chat": Änderungen für einen Kanal.
public struct ChatBatch: Decodable {
    public let channel: String
    public let updates: [ChatUpdate]

    private enum CodingKeys: String, CodingKey { case channel, updates }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channel = try container.decode(String.self, forKey: .channel)
        let raw = try container.decodeIfPresent([Lenient<ChatUpdate>].self, forKey: .updates) ?? []
        updates = raw.compactMap(\.value)
    }
}

/// Ereignis "chat-state": Verbindung des Alert-Dienstes zu Twitch.
public struct ChatState: Decodable, Equatable {
    public let channel: String
    public let connected: Bool
    public let error: String?
}

/// Ereignis "chat-assets": Badges und Emotes nachgeladen.
public struct ChatAssetsEvent: Decodable {
    public let channel: String
    public let assets: ChatAssets
}

/// Puffer der sichtbaren Zeilen: wendet Änderungen an und hält höchstens `limit` Zeilen.
public struct ChatBuffer: Equatable {
    public private(set) var lines: [ChatLine] = []
    public let limit: Int

    public init(limit: Int = 400) {
        self.limit = limit
    }

    public mutating func replace(with lines: [ChatLine]) {
        self.lines = Array(lines.suffix(limit))
    }

    public mutating func apply(_ updates: [ChatUpdate]) {
        for update in updates {
            switch update {
            case .line(let line):
                if lines.contains(where: { $0.id == line.id }) { continue }
                lines.append(line)
            case .delete(let id):
                lines = lines.map { line in
                    guard case .message(var message) = line, message.id == id else { return line }
                    message.deleted = true
                    return .message(message)
                }
            case .clearUser(let userId, let clear):
                lines = lines.map { line in
                    guard case .message(var message) = line, message.userId == userId else { return line }
                    message.cleared = clear
                    return .message(message)
                }
            case .clearAll(let at):
                lines = lines.map { line in
                    guard case .message(var message) = line, message.at <= at else { return line }
                    message.cleared = ChatClear(kind: "chat", seconds: nil, at: at)
                    return .message(message)
                }
            }
        }
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
    }
}
