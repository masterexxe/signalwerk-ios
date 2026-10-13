import Foundation
import Observation
import SignalwerkKit

/// Manuelle TTS: Text im OBS-Widget vorlesen lassen.
@MainActor
@Observable
final class SpeechStore {
    var text = ""
    var voice = "default"
    /// 0,7 bis 1,2; 1,0 heißt "Tempo der Stimme".
    var speed: Double = 1.0
    private(set) var voices: [Voice] = [Voice(value: "default", name: "Standard", speed: nil)]
    private(set) var sending = false
    /// Zuletzt gesendete Texte zum schnellen Wiederholen.
    private(set) var recent: [String] = []

    static let limit = 500
    private let context: SessionContext

    init(context: SessionContext) {
        self.context = context
    }

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var remaining: Int { SpeechStore.limit - trimmed.count }
    var canSend: Bool { !sending && !trimmed.isEmpty && remaining >= 0 }

    func load() async {
        do {
            voices = try await context.backend.voices()
            if !voices.contains(where: { $0.value == voice }) { voice = "default" }
        } catch {
            context.report(error)
        }
    }

    func send() async {
        guard canSend else { return }
        let message = trimmed
        sending = true
        defer { sending = false }
        do {
            let speedValue: Double? = abs(speed - 1.0) < 0.001 ? nil : (speed * 100).rounded() / 100
            let outcome = try await context.backend.speak(text: message, voice: voice, speed: speedValue)
            Haptics.success()
            context.show(outcome, success: "Wird vorgelesen.")
            text = ""
            recent.removeAll { $0 == message }
            recent.insert(message, at: 0)
            if recent.count > 5 { recent.removeLast(recent.count - 5) }
        } catch {
            Haptics.error()
            context.report(error)
        }
    }

    func reuse(_ message: String) {
        text = message
    }
}
