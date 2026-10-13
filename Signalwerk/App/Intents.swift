import AppIntents
import Foundation
import SignalwerkKit

// Kurzbefehle, Siri, Spotlight und die Aktionstaste: Notbremse, Test-Ton, Sounds, OBS-Widget
// und die offene Warteschlange, ohne die App zu öffnen. Benutzt dieselbe Anmeldung wie die
// App (Schlüsselbund); was das Konto nicht darf, lehnt das Dashboard ab.

/// Fehler, wie Kurzbefehle und Siri sie anzeigen.
enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:
            return "Signalwerk ist auf diesem Gerät nicht angemeldet. Bitte die App öffnen und anmelden."
        case .failed(let message):
            return "\(message)"
        }
    }
}

enum IntentAccess {
    static func backend() throws -> LiveBackend {
        guard let stored = TokenStore.load(), let server = URL(string: stored.server) else {
            throw IntentFailure.notSignedIn
        }
        return LiveBackend(server: server, token: stored.token)
    }

    /// Fehler des Dashboards als lesbaren Satz weiterreichen.
    static func run<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as SignalwerkError {
            throw IntentFailure.failed(error.errorDescription ?? "Signalwerk hat nicht geantwortet.")
        } catch {
            throw IntentFailure.failed(error.localizedDescription)
        }
    }
}

struct EmergencyStopIntent: AppIntent {
    static let title: LocalizedStringResource = "Notbremse ziehen"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let backend = try IntentAccess.backend()
        let outcome = try await IntentAccess.run { try await backend.emergencyStop() }
        let text = outcome.warning ?? "Notbremse gezogen. Alerts gestoppt, Warteschlange leer."
        return .result(dialog: "\(text)")
    }
}

struct TestAlertIntent: AppIntent {
    static let title: LocalizedStringResource = "Test-Ton abspielen"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let backend = try IntentAccess.backend()
        let outcome = try await IntentAccess.run { try await backend.testAlert() }
        let text = outcome.warning ?? "Test-Ton geschickt."
        return .result(dialog: "\(text)")
    }
}

struct ReloadWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "OBS-Widget neu laden"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let backend = try IntentAccess.backend()
        let outcome = try await IntentAccess.run { try await backend.reloadWidget() }
        let text = outcome.warning ?? "OBS-Widget lädt neu."
        return .result(dialog: "\(text)")
    }
}

/// „Was wartet?“: offene Spenden und Sub-Bombs, das nächste zuerst.
struct PendingQueueIntent: AppIntent {
    static let title: LocalizedStringResource = "Offene Spenden abfragen"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let backend = try IntentAccess.backend()
        let queue = try await IntentAccess.run { try await backend.queue(filter: .open) }
        let text = queue.spokenSummary
        return .result(dialog: "\(text)")
    }
}

/// Sound vom Soundboard, auswählbar in Kurzbefehle und per Siri („Welcher Sound?“).
struct SoundEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sound"
    static let defaultQuery = SoundQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SoundQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SoundEntity] {
        try await SoundQuery.all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [SoundEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sounds = try await SoundQuery.all()
        guard !needle.isEmpty else { return sounds }
        return sounds.filter { $0.name.lowercased().contains(needle) }
    }

    func suggestedEntities() async throws -> [SoundEntity] {
        try await SoundQuery.all()
    }

    static func all() async throws -> [SoundEntity] {
        let backend = try IntentAccess.backend()
        let response = try await IntentAccess.run { try await backend.sounds() }
        return response.sounds.map { SoundEntity(id: $0.id, name: $0.name) }
    }
}

struct PlaySoundIntent: AppIntent {
    static let title: LocalizedStringResource = "Sound abspielen"

    @Parameter(title: "Sound")
    var sound: SoundEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$sound) abspielen")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let backend = try IntentAccess.backend()
        let id = sound.id
        let outcome = try await IntentAccess.run { try await backend.playSound(id: id) }
        let text = outcome.warning ?? "\(sound.name) läuft."
        return .result(dialog: "\(text)")
    }
}

/// Erscheinen ohne Einrichtung in Kurzbefehle, Spotlight und Siri; die Notbremse passt auf die Aktionstaste.
struct SignalwerkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EmergencyStopIntent(),
            phrases: [
                "Notbremse in \(.applicationName)",
                "\(.applicationName) Notbremse ziehen",
                "Alerts in \(.applicationName) stoppen",
            ],
            shortTitle: "Notbremse",
            systemImageName: "exclamationmark.octagon.fill"
        )
        AppShortcut(
            intent: PendingQueueIntent(),
            phrases: [
                "Was wartet in \(.applicationName)",
                "Offene Spenden in \(.applicationName)",
            ],
            shortTitle: "Offene Spenden",
            systemImageName: "tray.full"
        )
        AppShortcut(
            intent: PlaySoundIntent(),
            phrases: [
                "Sound in \(.applicationName) abspielen",
                "\(.applicationName) Sound abspielen",
            ],
            shortTitle: "Sound abspielen",
            systemImageName: "speaker.wave.2.fill"
        )
        AppShortcut(
            intent: TestAlertIntent(),
            phrases: [
                "Test-Ton in \(.applicationName)",
                "\(.applicationName) Test-Ton abspielen",
            ],
            shortTitle: "Test-Ton",
            systemImageName: "bell.and.waves.left.and.right"
        )
        AppShortcut(
            intent: ReloadWidgetIntent(),
            phrases: [
                "OBS-Widget in \(.applicationName) neu laden",
                "\(.applicationName) Widget neu laden",
            ],
            shortTitle: "Widget neu laden",
            systemImageName: "arrow.clockwise"
        )
    }
}
