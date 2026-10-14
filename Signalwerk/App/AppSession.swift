import SwiftUI
import Observation
import SignalwerkKit

/// Gemeinsames für alle Bereiche einer Anmeldung: Zugang zum Dashboard, Rückmeldungen,
/// Umgang mit Fehlern. Kein UI-Zustand, daher nicht beobachtet.
@MainActor
final class SessionContext {
    let backend: SignalwerkBackend
    let toasts: ToastCenter
    /// Token ungültig oder Gerät entzogen: zurück zur Anmeldung.
    var onUnauthorized: ((String) -> Void)?

    init(backend: SignalwerkBackend, toasts: ToastCenter) {
        self.backend = backend
        self.toasts = toasts
    }

    func report(_ error: Error) {
        if error is CancellationError { return }
        if let known = error as? SignalwerkError {
            if case .cancelled = known { return }
            if known.isUnauthorized {
                onUnauthorized?(known.errorDescription ?? "Bitte neu anmelden.")
                return
            }
        }
        toasts.show(error: error)
    }

    /// Ergebnis einer Aktion zeigen: Hinweis vom Dashboard als Warnung, sonst der Erfolgstext.
    func show(_ outcome: ActionOutcome, success: String?) {
        if let warning = outcome.warning {
            toasts.show(warning, style: .warning, seconds: 4.5)
        } else if let success {
            toasts.show(success)
        }
    }
}

/// Eine Anmeldung: alle Bereiche der App und die Live-Ereignisse des Dashboards.
@MainActor
@Observable
final class AppSession {
    let context: SessionContext
    private(set) var me: MeResponse
    let queue: QueueStore
    let sounds: SoundsStore
    let speech: SpeechStore
    let overview: OverviewStore
    let chat: ChatStore
    let stats: StatsStore
    let devices: DevicesStore
    let liveVoice: LiveVoiceController
    let desk: DeskStore
    private(set) var stopping = false
    /// Live-Ereignisse verbunden?
    private(set) var live = false

    @ObservationIgnored var onMeUpdated: ((MeResponse) -> Void)?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(backend: SignalwerkBackend, me: MeResponse, toasts: ToastCenter) {
        let context = SessionContext(backend: backend, toasts: toasts)
        self.context = context
        self.me = me
        self.queue = QueueStore(context: context)
        self.sounds = SoundsStore(context: context)
        self.speech = SpeechStore(context: context)
        self.overview = OverviewStore(context: context)
        self.chat = ChatStore(context: context)
        self.stats = StatsStore(context: context)
        self.devices = DevicesStore(context: context)
        self.liveVoice = LiveVoiceController(context: context)
        self.desk = DeskStore(context: context)
    }

    var backend: SignalwerkBackend { context.backend }
    var toasts: ToastCenter { context.toasts }
    var isDemo: Bool { context.backend.isDemo }
    var user: UserInfo { me.user }

    func can(_ permission: Permission) -> Bool {
        me.permissions.contains(permission.rawValue)
    }

    /// Beim Start und wenn die App wieder nach vorne kommt.
    func activate() {
        eventsTask?.cancel()
        pollTask?.cancel()
        eventsTask = Task { [weak self] in
            await self?.listen()
        }
        // Zuschauerzahlen ändern sich ohne Ereignis; die Übersicht alle 30 Sekunden auffrischen.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.overview.load()
            }
        }
        Task { [weak self] in
            await self?.refreshAll()
            await self?.refreshMe()
        }
        chat.resume()
    }

    /// Im Hintergrund: keine Verbindungen offen halten.
    func deactivate() {
        // Ohne Hintergrund-Audio hört das Mikrofon im Hintergrund auf; Live-Voice sauber beenden.
        if liveVoice.isActive { Task { await liveVoice.stop() } }
        eventsTask?.cancel()
        eventsTask = nil
        pollTask?.cancel()
        pollTask = nil
        live = false
        chat.pause()
    }

    func end() {
        deactivate()
        chat.stop()
        sounds.stopPreview()
        Task { await liveVoice.stop() }
    }

    func refreshAll() async {
        await queue.load()
        await overview.load()
        await sounds.load()
        await speech.load()
    }

    func refreshMe() async {
        do {
            me = try await backend.me()
            onMeUpdated?(me)
        } catch {
            // Ohne Netz zählt der gespeicherte Stand; nur eine ungültige Anmeldung ist wichtig.
            if (error as? SignalwerkError)?.isUnauthorized == true { context.report(error) }
        }
    }

    private func listen() async {
        var delay: UInt64 = 1
        while !Task.isCancelled {
            do {
                for try await event in backend.events() {
                    delay = 1
                    switch event.name {
                    case "ready":
                        live = true
                    case "refresh":
                        await queue.load()
                        await overview.load()
                    case "revoked":
                        live = false
                        context.onUnauthorized?("Dieses Gerät wurde im Dashboard abgemeldet.")
                        return
                    default:
                        break
                    }
                }
            } catch {
                if (error as? SignalwerkError)?.isUnauthorized == true {
                    live = false
                    context.report(error)
                    return
                }
            }
            live = false
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(delay * 2, 30)
            // Nach einer Lücke alles nachladen.
            await queue.load()
        }
    }

    /// Notbremse: laufenden Alert abbrechen und alle Warteschlangen leeren.
    func emergencyStop() async {
        guard !stopping else { return }
        stopping = true
        Haptics.heavy()
        do {
            let outcome = try await backend.emergencyStop()
            if let warning = outcome.warning {
                toasts.show(warning, style: .warning, seconds: 5)
            } else {
                toasts.show("Notbremse gezogen. Alerts gestoppt, Warteschlange leer.")
            }
        } catch {
            Haptics.error()
            context.report(error)
        }
        stopping = false
    }

    func testAlert() async {
        do {
            let outcome = try await backend.testAlert()
            context.show(outcome, success: "Test-Ton geschickt.")
        } catch {
            context.report(error)
        }
    }

    func reloadWidget() async {
        do {
            let outcome = try await backend.reloadWidget()
            context.show(outcome, success: "OBS-Widget lädt neu.")
        } catch {
            context.report(error)
        }
    }
}
