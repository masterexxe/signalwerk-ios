import AVFoundation
import Foundation
import Observation
import SignalwerkKit

/// Soundboard: Tasten im OBS-Widget abspielen, auf dem Gerät vorhören.
@MainActor
@Observable
final class SoundsStore {
    private(set) var sounds: [Sound] = []
    private(set) var master = 100
    private(set) var loaded = false
    var query = ""
    /// Gerade an das Widget geschickt (Taste leuchtet kurz).
    private(set) var firing: String?
    private(set) var previewing: String?

    private let context: SessionContext
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init(context: SessionContext) {
        self.context = context
    }

    var visible: [Sound] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return sounds }
        return sounds.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    /// Ziffer der Taste: 1 bis 9 und 0 für die ersten zehn sichtbaren Sounds.
    static func hotkey(for index: Int) -> String? {
        guard index < 10 else { return nil }
        return index == 9 ? "0" : String(index + 1)
    }

    func load() async {
        do {
            let response = try await context.backend.sounds()
            sounds = response.sounds
            master = response.master
            loaded = true
        } catch {
            context.report(error)
        }
    }

    func play(_ sound: Sound) async {
        firing = sound.id
        Haptics.tap()
        do {
            let outcome = try await context.backend.playSound(id: sound.id)
            if let warning = outcome.warning { context.toasts.show(warning, style: .warning) }
        } catch {
            Haptics.error()
            context.report(error)
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        if firing == sound.id { firing = nil }
    }

    /// Nur hier hören, so laut wie im Widget (Gesamtlautstärke mal Sound).
    func preview(_ sound: Sound) {
        if previewing == sound.id {
            stopPreview()
            return
        }
        stopPreview()
        guard let url = URL(string: sound.previewUrl) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = Float(max(0, min(1, Double(master) / 100 * Double(sound.volume) / 100)))
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.previewing = nil
            }
        }
        self.player = player
        previewing = sound.id
        player.play()
    }

    func stopPreview() {
        player?.pause()
        player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        previewing = nil
    }
}
