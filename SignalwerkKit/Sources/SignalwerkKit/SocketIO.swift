import Foundation

/// Socket.IO 4 (Engine.IO 4) über WebSocket, so viel wie der Alert-Dienst braucht:
/// Ereignisse senden und empfangen, Bestätigungen (Acks), Ping/Pong, Binärdaten senden und
/// automatisch neu verbinden. Nur der Standard-Namespace "/".
public enum SocketPacket: Equatable {
    /// Engine.IO "0": Sitzung offen (Ping-Intervall in ms).
    case open(pingInterval: Int, pingTimeout: Int)
    /// Engine.IO "2"/"3".
    case ping
    case pong
    /// Engine.IO "1".
    case close
    /// Socket.IO "40": im Namespace angemeldet.
    case connected
    /// Socket.IO "41".
    case disconnected
    /// Socket.IO "44": Anmeldung abgelehnt.
    case connectError(String)
    /// Socket.IO "42[...]" mit optionaler Ack-ID; Argumente als JSON-Text.
    case event(name: String, argumentsJSON: String, ackId: Int?)
    /// Socket.IO "43<id>[...]".
    case ack(id: Int, argumentsJSON: String)
    /// Alles andere (Binärpakete an die App gibt es nicht).
    case unknown(String)
}

public enum SocketCodec {
    /// Textnachricht der WebSocket-Verbindung lesen.
    public static func parse(_ text: String) -> SocketPacket {
        guard let first = text.first else { return .unknown(text) }
        switch first {
        case "0":
            let json = String(text.dropFirst())
            let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
            return .open(pingInterval: object["pingInterval"] as? Int ?? 25000, pingTimeout: object["pingTimeout"] as? Int ?? 20000)
        case "1":
            return .close
        case "2":
            return .ping
        case "3":
            return .pong
        case "4":
            return parseMessage(String(text.dropFirst()))
        default:
            return .unknown(text)
        }
    }

    static func parseMessage(_ text: String) -> SocketPacket {
        guard let type = text.first else { return .unknown(text) }
        var rest = Substring(text.dropFirst())
        // Namespace "/x," wird nicht benutzt; sicherheitshalber überspringen.
        if rest.hasPrefix("/"), let comma = rest.firstIndex(of: ",") {
            rest = rest[rest.index(after: comma)...]
        }
        switch type {
        case "0":
            return .connected
        case "1":
            return .disconnected
        case "4":
            let object = (try? JSONSerialization.jsonObject(with: Data(rest.utf8))) as? [String: Any]
            return .connectError(object?["message"] as? String ?? "Verbindung abgelehnt.")
        case "2", "3":
            let digits = rest.prefix(while: { $0.isNumber })
            let ackId = digits.isEmpty ? nil : Int(digits)
            let json = String(rest.dropFirst(digits.count))
            if type == "3" {
                guard let ackId else { return .unknown(text) }
                return .ack(id: ackId, argumentsJSON: json)
            }
            guard let array = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Any],
                  let name = array.first as? String
            else { return .unknown(text) }
            let arguments = Array(array.dropFirst())
            let argumentsData = (try? JSONSerialization.data(withJSONObject: arguments, options: [])) ?? Data("[]".utf8)
            return .event(name: name, argumentsJSON: String(decoding: argumentsData, as: UTF8.self), ackId: ackId)
        default:
            return .unknown(text)
        }
    }

    /// "42<ack>[\"name\",…]".
    public static func encodeEvent(_ name: String, _ arguments: [Any], ackId: Int? = nil) -> String? {
        var payload: [Any] = [name]
        payload.append(contentsOf: arguments)
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])
        else { return nil }
        return "42" + (ackId.map(String.init) ?? "") + String(decoding: data, as: UTF8.self)
    }

    /// Binärereignis: "451-[\"name\",{\"_placeholder\":true,\"num\":0}]", danach die Daten als eigener Rahmen.
    public static func encodeBinaryEvent(_ name: String) -> String {
        "451-[\"\(name)\",{\"_placeholder\":true,\"num\":0}]"
    }

    /// Argumente (JSON-Array) als Typ lesen; meist ist das erste Argument gemeint.
    public static func decodeFirst<T: Decodable>(_ type: T.Type, from argumentsJSON: String) -> T? {
        guard let data = argumentsJSON.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let first = array.first,
              JSONSerialization.isValidJSONObject(first) || first is String || first is NSNumber
        else { return nil }
        let wrapped = (try? JSONSerialization.data(withJSONObject: [first], options: [])) ?? Data()
        return (try? JSONDecoder().decode([T].self, from: wrapped))?.first
    }
}

/// Takt für Binärereignisse (Live-Audio), ohne Netz und ohne Zustand, damit testbar.
public enum BinaryPacing {
    public enum Step: Equatable {
        /// Jetzt senden.
        case send
        /// Erst zu diesem Zeitpunkt wieder versuchen.
        case wait(DispatchTime)
        /// Nichts tun: nichts in der Spur, oder zu viel noch unterwegs.
        case hold
    }

    public static func next(now: DispatchTime, last: DispatchTime?, queued: Int, underway: Int) -> Step {
        guard queued > 0, underway < SocketIOClient.binaryInFlight else { return .hold }
        // Nach einem Stau doppelt so schnell aufholen, damit die Verzögerung nicht bleibt.
        let spacing = queued > 6 ? SocketIOClient.binarySpacing / 2 : SocketIOClient.binarySpacing
        guard let last else { return .send }
        let due = last + spacing
        return now < due ? .wait(due) : .send
    }
}

/// Verbindung zum Alert-Dienst. Der Zustand lebt auf einer eigenen Warteschlange, damit
/// Live-Audio nicht vom Main-Thread abhängt; Rückrufe (Status, Ereignisse) kommen auf dem Main-Thread.
public final class SocketIOClient: NSObject {
    public enum Status: Equatable {
        case idle
        case connecting
        case connected
        case disconnected(String?)
    }

    /// Abstand zwischen zwei Binärereignissen. Der Alert-Dienst leitet Live-Audio „volatile“
    /// weiter und verwirft, was ankommt, solange der vorige Rahmen noch zum Widget unterwegs ist.
    /// Das Mikrofon liefert 100 ms auf einmal (fünf Rahmen); als Stoß käme davon einer an.
    public static let binarySpacing: TimeInterval = 0.019
    /// So viele Binärereignisse dürfen warten (etwa 300 ms Ton); ältere fallen weg.
    public static let binaryBacklog = 15
    /// So viele Binärereignisse dürfen gleichzeitig unterwegs sein; danach wartet die Spur.
    public static let binaryInFlight = 6

    public var onStatus: ((Status) -> Void)?
    /// Ereignis vom Server: Name und Argumente als JSON-Text.
    public var onEvent: ((String, String) -> Void)?

    private let url: URL
    private let session: URLSession
    private let queue = DispatchQueue(label: "live.signalwerk.socketio", qos: .userInitiated)
    private var task: URLSessionWebSocketTask?
    private var acks: [Int: (Result<String, Error>) -> Void] = [:]
    private var nextAck = 0
    private var wantsConnection = false
    private var attempt = 0
    private var generation = 0
    private var namespaceReady = false
    private var pending: [URLSessionWebSocketTask.Message] = []
    private var binaryLane: [(name: String, data: Data)] = []
    private var binaryScheduled = false
    private var binaryUnderway = 0
    /// Zeitpunkt des letzten Binärereignisses. Optional, denn DispatchTime mit 0 hieße „jetzt“.
    private var lastBinary: DispatchTime?

    public init(server: URL, session: URLSession = .shared) {
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = (components.scheme == "http") ? "ws" : "wss"
        components.path = "/socket.io/"
        components.queryItems = [URLQueryItem(name: "EIO", value: "4"), URLQueryItem(name: "transport", value: "websocket")]
        self.url = components.url ?? server
        self.session = session
        super.init()
    }

    public static func socketURL(for server: URL) -> URL {
        SocketIOClient(server: server).url
    }

    public func connect() {
        queue.async {
            self.wantsConnection = true
            self.open()
        }
    }

    public func disconnect() {
        queue.async {
            self.wantsConnection = false
            self.generation += 1
            if self.namespaceReady, let task = self.task {
                task.send(.string("41")) { _ in }
            }
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            self.namespaceReady = false
            self.clearBinaryLane()
            self.failAcks(SignalwerkError.cancelled)
            self.report(.idle)
        }
    }

    /// Ereignis senden. Vor der Anmeldung im Namespace wird gepuffert.
    public func emit(_ name: String, _ arguments: [Any] = []) {
        guard let text = SocketCodec.encodeEvent(name, arguments) else { return }
        queue.async {
            self.send(.string(text))
        }
    }

    /// Ereignis mit Bestätigung; liefert die Antwort-Argumente als JSON-Text.
    public func emitWithAck(_ name: String, _ arguments: [Any] = [], timeout: TimeInterval = 8) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            queue.async {
                let id = self.nextAck
                self.nextAck += 1
                guard let text = SocketCodec.encodeEvent(name, arguments, ackId: id) else {
                    continuation.resume(throwing: SignalwerkError.invalidResponse("Ungültige Daten."))
                    return
                }
                var finished = false
                self.acks[id] = { result in
                    guard !finished else { return }
                    finished = true
                    continuation.resume(with: result)
                }
                self.send(.string(text))
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    if let callback = self.acks.removeValue(forKey: id) {
                        callback(.failure(SignalwerkError.network("Der Alert-Dienst antwortet nicht.")))
                    }
                }
            }
        }
    }

    /// Binärdaten als Ereignis (Live-Voice). Flüchtig wie `socket.volatile.emit` im Browser:
    /// Ohne Verbindung fällt der Rahmen weg, bei Rückstau der älteste. Gesendet wird im Takt
    /// von `binarySpacing`, nie als Stoß.
    public func emitBinary(_ name: String, _ data: Data) {
        queue.async {
            guard self.namespaceReady, self.task != nil else { return }
            self.binaryLane.append((name: name, data: data))
            let excess = self.binaryLane.count - SocketIOClient.binaryBacklog
            if excess > 0 { self.binaryLane.removeFirst(excess) }
            self.pumpBinary()
        }
    }

    // MARK: - intern (nur auf `queue`)

    private func report(_ status: Status) {
        let callback = onStatus
        DispatchQueue.main.async { callback?(status) }
    }

    private func send(_ message: URLSessionWebSocketTask.Message) {
        guard namespaceReady, let task else {
            if pending.count < 200 { pending.append(message) }
            return
        }
        task.send(message) { _ in }
    }

    private func pumpBinary() {
        guard !binaryScheduled, !binaryLane.isEmpty else { return }
        guard namespaceReady, let task else {
            binaryLane.removeAll()
            return
        }
        let now = DispatchTime.now()
        switch BinaryPacing.next(now: now, last: lastBinary, queued: binaryLane.count, underway: binaryUnderway) {
        case .hold:
            // Zu viel unterwegs: Der Abschluss eines Sendevorgangs stößt die Spur wieder an.
            return
        case .wait(let due):
            binaryScheduled = true
            queue.asyncAfter(deadline: due) { [weak self] in
                guard let self else { return }
                self.binaryScheduled = false
                self.pumpBinary()
            }
            return
        case .send:
            break
        }
        let next = binaryLane.removeFirst()
        lastBinary = now
        binaryUnderway += 1
        let current = generation
        task.send(.string(SocketCodec.encodeBinaryEvent(next.name))) { _ in }
        task.send(.data(next.data)) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard current == self.generation else { return }
                self.binaryUnderway = max(0, self.binaryUnderway - 1)
                self.pumpBinary()
            }
        }
        pumpBinary()
    }

    private func clearBinaryLane() {
        binaryLane.removeAll()
        binaryUnderway = 0
    }

    private func open() {
        guard wantsConnection, task == nil else { return }
        generation += 1
        let current = generation
        namespaceReady = false
        report(.connecting)
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 4 * 1024 * 1024
        self.task = task
        task.resume()
        receive(task, generation: current)
    }

    private func receive(_ task: URLSessionWebSocketTask, generation current: Int) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard current == self.generation else { return }
                switch result {
                case .failure(let error):
                    self.dropped(SignalwerkError.from(error).errorDescription)
                case .success(let message):
                    if case .string(let text) = message {
                        self.handle(text, task: task)
                    }
                    // handle() kann die Verbindung beendet haben.
                    if current == self.generation {
                        self.receive(task, generation: current)
                    }
                }
            }
        }
    }

    private func handle(_ text: String, task: URLSessionWebSocketTask) {
        switch SocketCodec.parse(text) {
        case .open:
            task.send(.string("40")) { _ in }
        case .ping:
            task.send(.string("3")) { _ in }
        case .connected:
            namespaceReady = true
            attempt = 0
            let queued = pending
            pending.removeAll()
            for message in queued { task.send(message) { _ in } }
            report(.connected)
        case .event(let name, let json, let ackId):
            let callback = onEvent
            DispatchQueue.main.async { callback?(name, json) }
            if let ackId { task.send(.string("43\(ackId)[]")) { _ in } }
        case .ack(let id, let json):
            acks.removeValue(forKey: id)?(.success(json))
        case .connectError(let message):
            dropped(message)
        case .disconnected, .close:
            dropped(nil)
        case .pong, .unknown:
            break
        }
    }

    private func failAcks(_ error: Error) {
        let callbacks = acks
        acks.removeAll()
        for callback in callbacks.values { callback(.failure(error)) }
    }

    private func dropped(_ reason: String?) {
        // Neue Generation: Späte Rückmeldungen der alten Verbindung zählen nicht mehr.
        generation += 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        namespaceReady = false
        clearBinaryLane()
        failAcks(SignalwerkError.network(reason ?? "Verbindung zum Alert-Dienst getrennt."))
        report(.disconnected(reason))
        guard wantsConnection else { return }
        attempt += 1
        let delay = min(15.0, pow(2.0, Double(min(attempt, 4))) * 0.5)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.open()
        }
    }
}
