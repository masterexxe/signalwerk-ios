import Foundation

public enum ChatConnection: Equatable {
    case idle
    case connecting
    case live
    case offline(String?)
}

/// Quelle der Chat-Zeilen: der Alert-Dienst (Socket.IO) oder die Demo.
/// Rückrufe kommen auf dem Main-Thread.
public protocol ChatSource: AnyObject {
    var onConnection: ((ChatConnection) -> Void)? { get set }
    var onUpdates: ((String, [ChatUpdate]) -> Void)? { get set }
    var onAssets: ((String, ChatAssets) -> Void)? { get set }
    var onState: ((ChatState) -> Void)? { get set }

    func start()
    func stop()
    func join(channel: String) async throws -> ChatJoinReply
    func leave(channel: String)
    /// Verlauf eines Nutzers aus dem Puffer des Alert-Dienstes.
    func history(channel: String, userId: String, login: String) async throws -> [ChatLine]
}

/// Chat über den Alert-Dienst, wie im Arbeitsbereich: Ticket vom Dashboard, dann "chat-join".
public final class LiveChatSource: ChatSource {
    public var onConnection: ((ChatConnection) -> Void)?
    public var onUpdates: ((String, [ChatUpdate]) -> Void)?
    public var onAssets: ((String, ChatAssets) -> Void)?
    public var onState: ((ChatState) -> Void)?

    private let backend: SignalwerkBackend
    private var socket: SocketIOClient?
    private var ticket: ChatTicket?
    /// Zählt Starts und Stopps: Ein Start, dessen Ticket erst nach einem Stopp kommt, verbindet nicht mehr.
    private var attempt = 0

    public init(backend: SignalwerkBackend) {
        self.backend = backend
    }

    public func start() {
        guard socket == nil else { return }
        attempt += 1
        let current = attempt
        onConnection?(.connecting)
        Task { @MainActor in
            do {
                let ticket = try await self.backend.chatTicket()
                guard current == self.attempt, self.socket == nil else { return }
                self.ticket = ticket
                let url = URL(string: ticket.socketUrl) ?? self.backend.serverURL
                let socket = SocketIOClient(server: url)
                // Meldungen einer schon ersetzten Verbindung (Pause, Neustart) nicht mehr zeigen.
                socket.onStatus = { [weak self, weak socket] status in
                    guard let self, let socket, self.socket === socket else { return }
                    switch status {
                    case .idle: self.onConnection?(.idle)
                    case .connecting: self.onConnection?(.connecting)
                    case .connected: self.onConnection?(.live)
                    case .disconnected(let reason): self.onConnection?(.offline(reason))
                    }
                }
                socket.onEvent = { [weak self, weak socket] name, json in
                    guard let self, let socket, self.socket === socket else { return }
                    self.handle(name, json)
                }
                self.socket = socket
                socket.connect()
            } catch {
                guard current == self.attempt else { return }
                self.onConnection?(.offline((error as? SignalwerkError)?.errorDescription ?? error.localizedDescription))
            }
        }
    }

    public func stop() {
        attempt += 1
        socket?.disconnect()
        socket = nil
    }

    private func handle(_ name: String, _ json: String) {
        switch name {
        case "chat":
            if let batch = SocketCodec.decodeFirst(ChatBatch.self, from: json) {
                onUpdates?(batch.channel, batch.updates)
            }
        case "chat-state":
            if let state = SocketCodec.decodeFirst(ChatState.self, from: json) {
                onState?(state)
            }
        case "chat-assets":
            if let event = SocketCodec.decodeFirst(ChatAssetsEvent.self, from: json) {
                onAssets?(event.channel, event.assets)
            }
        default:
            break
        }
    }

    public func join(channel: String) async throws -> ChatJoinReply {
        guard let socket else { throw SignalwerkError.network("Chat nicht verbunden.") }
        if ticket == nil { ticket = try await backend.chatTicket() }
        var reply = try await joinOnce(socket, channel: channel)
        if !reply.ok, (reply.error ?? "").contains("abgelaufen") {
            // Ticket gilt 12 Stunden; danach ein neues holen und noch einmal.
            ticket = try await backend.chatTicket()
            reply = try await joinOnce(socket, channel: channel)
        }
        if !reply.ok { throw SignalwerkError.server(status: 400, message: reply.error ?? "Chat nicht verfügbar.") }
        return reply
    }

    private func joinOnce(_ socket: SocketIOClient, channel: String) async throws -> ChatJoinReply {
        let json = try await socket.emitWithAck("chat-join", [["token": ticket?.token ?? "", "channel": channel]])
        guard let reply = SocketCodec.decodeFirst(ChatJoinReply.self, from: json) else {
            throw SignalwerkError.invalidResponse("Antwort des Alert-Dienstes nicht lesbar.")
        }
        return reply
    }

    public func leave(channel: String) {
        socket?.emit("chat-leave", [["channel": channel]])
    }

    public func history(channel: String, userId: String, login: String) async throws -> [ChatLine] {
        guard let socket else { throw SignalwerkError.network("Chat nicht verbunden.") }
        let json = try await socket.emitWithAck("chat-user", [["channel": channel, "userId": userId, "login": login]])
        struct Reply: Decodable {
            let ok: Bool
            let lines: [Lenient<ChatLine>]?
            let error: String?
        }
        guard let reply = SocketCodec.decodeFirst(Reply.self, from: json) else { return [] }
        if !reply.ok { throw SignalwerkError.server(status: 400, message: reply.error ?? "Verlauf nicht verfügbar.") }
        return (reply.lines ?? []).compactMap(\.value)
    }
}

/// Chat der Demo: ein paar Zeilen zum Start, danach regelmäßig neue.
public final class DemoChatSource: ChatSource {
    public var onConnection: ((ChatConnection) -> Void)?
    public var onUpdates: ((String, [ChatUpdate]) -> Void)?
    public var onAssets: ((String, ChatAssets) -> Void)?
    public var onState: ((ChatState) -> Void)?

    private var timer: Timer?
    private var counter = 0
    private let live: Bool
    private var channel = "signalwerk_live"

    public init(live: Bool = true) {
        self.live = live
    }

    public func start() {
        onConnection?(.live)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func join(channel: String) async throws -> ChatJoinReply {
        self.channel = channel
        if live {
            await MainActor.run {
                self.timer?.invalidate()
                self.timer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
                    self?.tick()
                }
            }
        }
        return ChatJoinReply(ok: true, channel: channel, connected: true, lines: DemoChatSource.backlog(now: Date()), assets: nil, error: nil)
    }

    public func leave(channel: String) {
        timer?.invalidate()
        timer = nil
    }

    public func history(channel: String, userId: String, login: String) async throws -> [ChatLine] {
        DemoChatSource.backlog(now: Date()).filter { $0.userId == userId }
    }

    static let people: [(String, String, String, [String])] = [
        ("101", "MaxPower", "#FF7F50", ["subscriber/12"]),
        ("102", "Lea_K", "#1E90FF", ["subscriber/12", "vip/1"]),
        ("103", "ByteWolf", "#9ACD32", ["subscriber/3"]),
        ("104", "LunaPxl", "#DA70D6", []),
        ("105", "TobiBaut", "#00CED1", ["subscriber/6"]),
        ("106", "MiraMC", "#FFB224", ["moderator/1"]),
        ("107", "Kai_88", "#63C5FF", ["subscriber/0"]),
    ]

    static let texts: [String] = [
        "Der Sound war zu gut 😂",
        "Kappa wie lange geht der Stream heute noch?",
        "Grüße aus Köln!",
        "@MiraMC danke für die Info",
        "Wann ist das nächste Event?",
        "PogChamp was ein Drop",
        "Kamera 2 hängt kurz, oder ist das nur bei mir?",
        "GG!",
        "Trommelwirbel bitte 🥁",
        "Die neue Grafik sieht richtig gut aus",
    ]

    static func message(_ index: Int, at date: Date) -> ChatLine {
        let person = people[index % people.count]
        let text = texts[index % texts.count]
        var emotes: [ChatEmote] = []
        if text.hasPrefix("Kappa") { emotes = [ChatEmote(id: "25", start: 0, end: 4)] }
        if text.hasPrefix("PogChamp") { emotes = [ChatEmote(id: "305954156", start: 0, end: 7)] }
        return .message(ChatMessage(
            id: "demo-\(index)-\(Int(date.timeIntervalSince1970))",
            at: date.timeIntervalSince1970 * 1000,
            userId: person.0,
            login: person.1.lowercased(),
            name: person.1,
            color: person.2,
            badges: person.3,
            months: person.3.contains("subscriber/12") ? 14 : 0,
            text: text,
            emotes: emotes,
            first: index == 3
        ))
    }

    static func backlog(now: Date) -> [ChatLine] {
        var lines: [ChatLine] = (0..<12).map { message($0, at: now.addingTimeInterval(Double($0 - 12) * 25)) }
        lines.insert(.notice(ChatNotice(
            id: "demo-raid",
            at: now.addingTimeInterval(-200).timeIntervalSince1970 * 1000,
            type: "raid",
            userId: "200",
            login: "anderer_kanal",
            name: "Anderer_Kanal",
            color: "#FF4B3E",
            badges: [],
            system: "Raid von Anderer_Kanal mit 87 Zuschauern.",
            text: "",
            emotes: []
        )), at: 5)
        lines.append(.system(ChatSystemLine(id: "demo-timeout", at: now.addingTimeInterval(-30).timeIntervalSince1970 * 1000, tone: "timeout", text: "Timeout für troll99: 10 min", userId: "999", login: "troll99")))
        return lines
    }

    private func tick() {
        counter += 1
        onUpdates?(channel, [.line(DemoChatSource.message(counter + 12, at: Date()))])
    }
}

extension ChatJoinReply {
    public init(ok: Bool, channel: String?, connected: Bool?, lines: [ChatLine], assets: ChatAssets?, error: String?) {
        self.ok = ok
        self.channel = channel
        self.connected = connected
        self.lines = lines
        self.assets = assets
        self.error = error
    }
}
