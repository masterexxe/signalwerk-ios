import Foundation
import Observation
import SignalwerkKit

/// Twitch-Chat über den Alert-Dienst: mitlesen, schreiben, moderieren.
@MainActor
@Observable
final class ChatStore {
    private(set) var buffer = ChatBuffer(limit: 300)
    private(set) var assets = ChatAssets.empty
    private(set) var connection: ChatConnection = .idle
    /// Verbindung des Alert-Dienstes zu Twitch.
    private(set) var twitchConnected = true
    private(set) var twitchError: String?
    private(set) var channels: [Channel] = []
    private(set) var channel: String?
    private(set) var joining = false
    private(set) var sending = false
    var draft = ""
    var replyTo: ChatMessage?

    private let context: SessionContext
    @ObservationIgnored private var source: ChatSource?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var paused = false

    init(context: SessionContext) {
        self.context = context
    }

    var lines: [ChatLine] { buffer.lines }

    func start() async {
        guard !started else { return }
        started = true
        do {
            let response = try await context.backend.channels()
            channels = response.channels
            if channel == nil {
                channel = response.defaultLogin.isEmpty ? response.channels.first?.login : response.defaultLogin
            }
        } catch {
            context.report(error)
        }
        connect()
    }

    private func connect() {
        guard source == nil else { return }
        let source: ChatSource = context.backend.isDemo ? DemoChatSource() : LiveChatSource(backend: context.backend)
        source.onConnection = { [weak self] state in
            MainActor.assumeIsolated { self?.connectionChanged(state) }
        }
        source.onUpdates = { [weak self] channel, updates in
            MainActor.assumeIsolated { self?.received(channel, updates) }
        }
        source.onAssets = { [weak self] channel, assets in
            MainActor.assumeIsolated {
                guard let self, channel == self.channel else { return }
                self.assets = assets
            }
        }
        source.onState = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, state.channel == self.channel else { return }
                self.twitchConnected = state.connected
                self.twitchError = state.error
            }
        }
        self.source = source
        source.start()
    }

    /// App im Hintergrund: Verbindung schließen; beim Zurückkommen neu verbinden.
    func pause() {
        guard started else { return }
        paused = true
        source?.stop()
        source = nil
        connection = .idle
    }

    func resume() {
        guard started, paused else { return }
        paused = false
        connect()
    }

    func stop() {
        source?.stop()
        source = nil
        started = false
        connection = .idle
    }

    private func connectionChanged(_ state: ChatConnection) {
        connection = state
        if state == .live, let channel {
            Task { await join(channel) }
        }
    }

    private func received(_ channel: String, _ updates: [ChatUpdate]) {
        guard channel == self.channel else { return }
        buffer.apply(updates)
    }

    func join(_ login: String) async {
        guard let source else { return }
        joining = true
        defer { joining = false }
        do {
            let reply = try await source.join(channel: login)
            guard login == channel else { return }
            buffer.replace(with: reply.lines)
            if let assets = reply.assets { self.assets = assets }
            twitchConnected = reply.connected ?? true
            twitchError = nil
        } catch {
            context.report(error)
        }
    }

    func select(_ login: String) {
        guard login != channel else { return }
        if let old = channel { source?.leave(channel: old) }
        channel = login
        buffer = ChatBuffer(limit: 300)
        assets = .empty
        Task { await join(login) }
    }

    var canSend: Bool {
        !sending && channel != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send() async {
        guard canSend, let channel else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        defer { sending = false }
        do {
            let outcome = try await context.backend.sendChat(channel: channel, text: text, replyTo: replyTo?.id)
            draft = ""
            replyTo = nil
            if let warning = outcome.warning { context.toasts.show(warning, style: .warning) }
            if context.backend.isDemo {
                // In der Demo erscheint die eigene Nachricht sofort.
                buffer.apply([.line(.message(ChatMessage(id: UUID().uuidString, at: Date().timeIntervalSince1970 * 1000, userId: "demo", login: "demo", name: "Demo", color: "#FFB224", badges: ["moderator/1"], months: 0, text: text, emotes: [])))])
            }
        } catch {
            Haptics.error()
            context.report(error)
        }
    }

    func moderate(_ message: ChatMessage, action: String, seconds: Int? = nil) async {
        guard let channel else { return }
        do {
            let text = try await context.backend.moderate(ModerationRequest(
                action: action,
                channel: channel,
                userId: message.userId,
                login: message.login,
                messageId: action == "delete" ? message.id : nil,
                seconds: seconds
            ))
            Haptics.success()
            context.toasts.show(text)
        } catch {
            Haptics.error()
            context.report(error)
        }
    }

    /// Verlauf eines Nutzers aus dem Puffer des Alert-Dienstes; ohne Verbindung die sichtbaren Zeilen.
    func history(for message: ChatMessage) async -> [ChatLine] {
        let visible = lines.filter { $0.userId == message.userId }
        guard let source, let channel else { return visible }
        do {
            let lines = try await source.history(channel: channel, userId: message.userId, login: message.login)
            return lines.isEmpty ? visible : lines
        } catch {
            return visible
        }
    }

    /// Bilder der Badges einer Nachricht (falls bekannt).
    func badgeImages(_ badges: [String]) -> [ChatBadgeImage] {
        badges.compactMap { assets.badges[$0] }
    }
}
