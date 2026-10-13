import Foundation

/// Alles, was die App vom Dashboard braucht. `LiveBackend` spricht mit dem Server,
/// `DemoBackend` spielt Signalwerk ohne Server vor (Demo, Vorschauen, UI-Tests).
public protocol SignalwerkBackend: AnyObject {
    var isDemo: Bool { get }
    var serverURL: URL { get }

    func me() async throws -> MeResponse
    func overview() async throws -> Overview
    func queue(filter: QueueFilter) async throws -> QueueResponse
    func decide(_ item: QueueItem, action: QueueAction) async throws -> ActionOutcome
    func sounds() async throws -> SoundsResponse
    func playSound(id: String) async throws -> ActionOutcome
    func voices() async throws -> [Voice]
    func speak(text: String, voice: String, speed: Double?) async throws -> ActionOutcome
    func emergencyStop() async throws -> ActionOutcome
    func testAlert() async throws -> ActionOutcome
    func reloadWidget() async throws -> ActionOutcome
    func channels() async throws -> ChannelsResponse
    func stream(login: String?) async throws -> StreamSnapshot
    func chatTicket() async throws -> ChatTicket
    func sendChat(channel: String, text: String, replyTo: String?) async throws -> ActionOutcome
    func moderate(_ request: ModerationRequest) async throws -> String
    func openLiveVoice() async throws -> LiveVoiceSession
    func devices() async throws -> DevicesResponse
    func revokeDevice(id: String) async throws
    func registerPush(token: String?, environment: String, queue: Bool) async throws
    /// Test-Mitteilung an dieses Gerät.
    func testPush() async throws
    func logout() async throws
    /// Live-Ereignisse ("refresh", wenn sich Spenden oder Sounds ändern). Endet bei Fehlern.
    func events() -> AsyncThrowingStream<ServerEvent, Error>
}

/// Anmeldung am Dashboard, bevor es ein Token gibt.
public enum SignalwerkLogin {
    /// Mit E-Mail und Passwort (Team-Zugang).
    public static func password(server: URL, email: String, password: String, deviceName: String, platform: String) async throws -> SessionPayload {
        let client = SignalwerkClient(baseURL: server)
        return try await client.send(
            SessionPayload.self,
            "POST",
            "/auth/password",
            body: ["email": email, "password": password, "device": ["name": deviceName, "platform": platform]],
            authorized: false
        )
    }

    /// Code aus der Anmeldung über die Webseite gegen das Token tauschen.
    public static func exchange(server: URL, code: String, verifier: String) async throws -> SessionPayload {
        let client = SignalwerkClient(baseURL: server)
        return try await client.send(SessionPayload.self, "POST", "/auth/token", body: ["code": code, "verifier": verifier], authorized: false)
    }
}

public final class LiveBackend: SignalwerkBackend {
    public let client: SignalwerkClient
    public var isDemo: Bool { false }
    public var serverURL: URL { client.baseURL }

    public init(server: URL, token: String) {
        self.client = SignalwerkClient(baseURL: server, token: token)
    }

    public func me() async throws -> MeResponse {
        try await client.send(MeResponse.self, "GET", "/me")
    }

    public func overview() async throws -> Overview {
        try await client.send(Overview.self, "GET", "/overview")
    }

    public func queue(filter: QueueFilter) async throws -> QueueResponse {
        try await client.send(QueueResponse.self, "GET", "/queue", query: [URLQueryItem(name: "filter", value: filter.rawValue)])
    }

    public func decide(_ item: QueueItem, action: QueueAction) async throws -> ActionOutcome {
        let result = try await client.action(Ignored.self, "/queue/decide", body: ["kind": item.kind, "id": item.id, "action": action.rawValue])
        return ActionOutcome(warning: result.warning)
    }

    public func sounds() async throws -> SoundsResponse {
        try await client.send(SoundsResponse.self, "GET", "/sounds")
    }

    public func playSound(id: String) async throws -> ActionOutcome {
        let result = try await client.action(Ignored.self, "/sounds/play", body: ["id": id])
        return ActionOutcome(warning: result.warning)
    }

    public func voices() async throws -> [Voice] {
        try await client.send(VoicesResponse.self, "GET", "/voices").voices
    }

    public func speak(text: String, voice: String, speed: Double?) async throws -> ActionOutcome {
        var body: [String: Any] = ["text": text, "voice": voice]
        if let speed { body["speed"] = speed }
        let result = try await client.action(Ignored.self, "/tts", body: body)
        return ActionOutcome(warning: result.warning)
    }

    public func emergencyStop() async throws -> ActionOutcome {
        let result = try await client.action(StopResult.self, "/ops/stop")
        return ActionOutcome(warning: result.warning)
    }

    public func testAlert() async throws -> ActionOutcome {
        let result = try await client.action(Ignored.self, "/ops/test-alert")
        return ActionOutcome(warning: result.warning)
    }

    public func reloadWidget() async throws -> ActionOutcome {
        let result = try await client.action(Ignored.self, "/ops/reload-widget")
        return ActionOutcome(warning: result.warning)
    }

    public func channels() async throws -> ChannelsResponse {
        try await client.send(ChannelsResponse.self, "GET", "/chat/channels")
    }

    public func stream(login: String?) async throws -> StreamSnapshot {
        let query = login.map { [URLQueryItem(name: "login", value: $0)] } ?? []
        return try await client.send(StreamSnapshot.self, "GET", "/stream", query: query)
    }

    public func chatTicket() async throws -> ChatTicket {
        let result = try await client.action(ChatTicket.self, "/chat/ticket")
        guard let ticket = result.data else { throw SignalwerkError.invalidResponse("Kein Chat-Ticket erhalten.") }
        return ticket
    }

    public func sendChat(channel: String, text: String, replyTo: String?) async throws -> ActionOutcome {
        var body: [String: Any] = ["channel": channel, "text": text]
        if let replyTo { body["replyTo"] = replyTo }
        let result = try await client.action(Ignored.self, "/chat/send", body: body)
        return ActionOutcome(warning: result.warning)
    }

    public func moderate(_ request: ModerationRequest) async throws -> String {
        var body: [String: Any] = ["channel": request.channel, "action": request.action, "userId": request.userId, "login": request.login]
        if let messageId = request.messageId { body["messageId"] = messageId }
        if let seconds = request.seconds { body["seconds"] = seconds }
        if let reason = request.reason, !reason.isEmpty { body["reason"] = reason }
        let result = try await client.action(ModerationResult.self, "/chat/moderate", body: body)
        return result.data?.text ?? "Erledigt."
    }

    public func openLiveVoice() async throws -> LiveVoiceSession {
        let result = try await client.action(LiveVoiceSession.self, "/live-voice/open")
        guard let session = result.data else { throw SignalwerkError.invalidResponse("Keine Live-Voice-Sitzung erhalten.") }
        return session
    }

    public func devices() async throws -> DevicesResponse {
        try await client.send(DevicesResponse.self, "GET", "/devices")
    }

    public func revokeDevice(id: String) async throws {
        _ = try await client.send(Ignored.self, "POST", "/devices/revoke", body: ["id": id])
    }

    public func registerPush(token: String?, environment: String, queue: Bool) async throws {
        let body: [String: Any] = [
            "token": token ?? NSNull(),
            "environment": environment,
            "prefs": ["queue": queue],
        ]
        _ = try await client.send(Ignored.self, "PUT", "/devices/push", body: body)
    }

    public func testPush() async throws {
        _ = try await client.send(Ignored.self, "POST", "/devices/push/test")
    }

    public func logout() async throws {
        _ = try await client.send(Ignored.self, "POST", "/auth/logout")
    }

    public func events() -> AsyncThrowingStream<ServerEvent, Error> {
        EventStream.open(request: (try? client.makeRequest("GET", "/events")), session: client.session)
    }
}
