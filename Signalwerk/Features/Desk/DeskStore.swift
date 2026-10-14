import Foundation
import Observation
import SignalwerkKit

/// Bereiche unter dem Player im Arbeitsbereich.
enum DeskTab: String, CaseIterable, Identifiable {
    case queue
    case sounds
    case tts
    case voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queue: return "Spenden"
        case .sounds: return "Sounds"
        case .tts: return "TTS"
        case .voice: return "Live-Voice"
        }
    }
}

/// Arbeitsbereich: welcher Kanal im Player läuft, ob der Player offen ist und welcher Bereich
/// darunter gewählt ist. Kanal und Player-Zustand merkt sich das Gerät.
@MainActor
@Observable
final class DeskStore {
    var tab: DeskTab = .queue
    private(set) var channels: [Channel] = []
    private(set) var channel: String?
    private(set) var playerOpen: Bool
    /// Kanäle geladen, aber keiner eingerichtet.
    private(set) var noChannel = false

    @ObservationIgnored private let context: SessionContext
    @ObservationIgnored private var loaded = false

    private static let channelKey = "signalwerk.desk.channel"
    private static let playerKey = "signalwerk.desk.player"

    init(context: SessionContext) {
        self.context = context
        self.playerOpen = UserDefaults.standard.object(forKey: DeskStore.playerKey) as? Bool ?? true
        let stored = UserDefaults.standard.string(forKey: DeskStore.channelKey) ?? ""
        self.channel = stored.isEmpty ? nil : stored
    }

    func load() async {
        guard !loaded else { return }
        do {
            let response = try await context.backend.channels()
            loaded = true
            channels = response.channels
            // Gemerkter Kanal, solange es ihn noch gibt; sonst der Standardkanal des Dashboards.
            if let current = channel, response.channels.contains(where: { $0.login == current }) { return }
            channel = response.defaultLogin.isEmpty ? response.channels.first?.login : response.defaultLogin
            noChannel = channel == nil
        } catch {
            context.report(error)
        }
    }

    func select(_ login: String) {
        channel = login
        noChannel = false
        UserDefaults.standard.set(login, forKey: DeskStore.channelKey)
    }

    func togglePlayer() {
        playerOpen.toggle()
        UserDefaults.standard.set(playerOpen, forKey: DeskStore.playerKey)
    }

    var channelName: String {
        channels.first(where: { $0.login == channel })?.displayName ?? channel ?? "Kanal"
    }
}
