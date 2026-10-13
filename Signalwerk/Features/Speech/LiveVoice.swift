import AVFoundation
import Foundation
import Observation
import SignalwerkKit
import SwiftUI

/// Live-Voice: Mikrofon live ins OBS-Widget, über den Alert-Dienst wie im Arbeitsbereich.
///
/// Ablauf: Sitzung im Dashboard öffnen (Token), Socket.IO verbinden, als "sender" beitreten,
/// dann 20-ms-Rahmen schicken: 8 Byte Kopf (Folgenummer, Abtastrate, je uint32 little endian)
/// und PCM 16 Bit mono mit 24 kHz (lib/alerts/live-relay.ts im Dashboard).
@MainActor
@Observable
final class LiveVoiceController {
    enum Phase: Equatable {
        case idle
        case preparing
        case live
    }

    private(set) var phase: Phase = .idle
    private(set) var startedAt: Date?
    /// Pegel 0…1 für die Anzeige.
    private(set) var level: Double = 0
    /// Widgets, die gerade abspielen (aus "live-status").
    private(set) var listeners: [String: Bool] = [:]
    private(set) var statusText = "Bereit."
    private(set) var error: String?

    private let context: SessionContext
    @ObservationIgnored private var socket: SocketIOClient?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private let packer = LiveFramePacker()

    init(context: SessionContext) {
        self.context = context
    }

    var isActive: Bool { phase != .idle }
    var playingWidgets: Int { listeners.values.filter { $0 }.count }

    func toggle() async {
        if isActive {
            await stop()
        } else {
            await start()
        }
    }

    func start() async {
        guard phase == .idle else { return }
        error = nil
        phase = .preparing
        statusText = "Mikrofon wird freigegeben …"
        guard await AVAudioApplication.requestRecordPermission() else {
            fail("Kein Zugriff aufs Mikrofon. In den iOS-Einstellungen für Signalwerk erlauben.")
            return
        }
        statusText = "Sitzung wird geöffnet …"
        let session: LiveVoiceSession
        do {
            session = try await context.backend.openLiveVoice()
        } catch {
            context.report(error)
            fail((error as? LocalizedError)?.errorDescription ?? "Live-Voice ließ sich nicht öffnen.")
            return
        }
        guard phase == .preparing else { return }
        let url = URL(string: session.socketUrl) ?? context.backend.serverURL
        let socket = SocketIOClient(server: url)
        // Späte Meldungen einer schon beendeten Verbindung dürfen eine neue Sitzung nicht stören.
        socket.onStatus = { [weak self, weak socket] status in
            MainActor.assumeIsolated {
                guard let self, let socket, self.socket === socket else { return }
                self.socketChanged(status, token: session.token)
            }
        }
        socket.onEvent = { [weak self, weak socket] name, json in
            MainActor.assumeIsolated {
                guard let self, let socket, self.socket === socket else { return }
                self.received(name, json)
            }
        }
        self.socket = socket
        statusText = "Verbindet …"
        socket.connect()
    }

    private func socketChanged(_ status: SocketIOClient.Status, token: String) {
        switch status {
        case .connected:
            guard phase == .preparing, let socket else { return }
            socket.emit("join", [["room": "", "token": token, "role": "sender"]])
            do {
                try startCapture()
                phase = .live
                startedAt = Date()
                statusText = "Wartet auf das OBS-Widget."
                Haptics.success()
            } catch {
                fail((error as? LocalizedError)?.errorDescription ?? "Mikrofon ließ sich nicht starten.")
            }
        case .disconnected(let reason):
            if phase != .idle {
                fail(reason.map { "Verbindung verloren: \($0)" } ?? "Verbindung verloren. Live-Voice wurde beendet.")
            }
        case .idle, .connecting:
            break
        }
    }

    private func received(_ name: String, _ json: String) {
        switch name {
        case "live-voice":
            guard let event = SocketCodec.decodeFirst(LiveVoiceEvent.self, from: json) else { return }
            switch event.type {
            case "viewer-ready":
                if let id = event.viewerId { listeners[id] = listeners[id] ?? false }
                statusText = "OBS-Widget verbunden, Ton geht über den Server."
            case "viewer-left":
                if let id = event.viewerId { listeners.removeValue(forKey: id) }
                if listeners.isEmpty { statusText = "Wartet auf das OBS-Widget." }
            case "replaced":
                shutdown(message: "Eine andere Sitzung hat Live-Voice übernommen.")
            case "stopped":
                shutdown(message: "Live-Voice wurde beendet.")
            default:
                break
            }
        case "live-status":
            guard let status = SocketCodec.decodeFirst(LiveVoiceStatusEvent.self, from: json) else { return }
            listeners[status.viewerId] = status.playing
            if status.playing { statusText = "Im Stream zu hören." }
        default:
            break
        }
    }

    func stop() async {
        guard phase != .idle else { return }
        if let socket {
            _ = try? await socket.emitWithAck("live-stop", [], timeout: 1.5)
        }
        shutdown(message: "Live-Voice beendet.")
    }

    private func fail(_ message: String) {
        shutdown(message: "Bereit.")
        error = message
        Haptics.error()
    }

    private func shutdown(message: String) {
        stopCapture()
        socket?.disconnect()
        socket = nil
        phase = .idle
        startedAt = nil
        listeners = [:]
        level = 0
        statusText = message
    }

    // MARK: - Mikrofon

    private func startCapture() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try audio.setActive(true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Echo- und Rauschunterdrückung wie im Browser (echoCancellation, noiseSuppression).
        try? input.setVoiceProcessingEnabled(true)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw SignalwerkError.invalidResponse("Kein Mikrofon gefunden.")
        }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(LiveFramePacker.sampleRate), channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: target)
        else {
            throw SignalwerkError.invalidResponse("Audioformat wird nicht unterstützt.")
        }
        guard let socket = self.socket else {
            throw SignalwerkError.network("Keine Verbindung zum Alert-Dienst.")
        }
        packer.reset()
        let tap = LiveFramePacker.tapBlock(converter: converter, target: target, packer: packer, socket: socket) { [weak self] rms in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.level = self.level * 0.6 + min(1, rms * 4) * 0.4
                }
            }
        }
        // iOS liefert 100 bis 400 ms je Abgriff; der Socket verteilt die Rahmen im 20-ms-Takt.
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(inputFormat.sampleRate / 10), format: inputFormat, block: tap)
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func stopCapture() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

struct LiveVoiceEvent: Decodable {
    let type: String
    let viewerId: String?
}

struct LiveVoiceStatusEvent: Decodable {
    let viewerId: String
    let playing: Bool
}

/// Rahmen für den Alert-Dienst bauen. Läuft auf dem Audio-Thread, daher eigener Lock.
final class LiveFramePacker {
    static let sampleRate: UInt32 = 24_000
    /// 20 ms bei 24 kHz.
    static let frameSamples = 480

    private let lock = NSLock()
    private var pending: [Int16] = []
    private var sequence: UInt32 = 0
    private var lastLevel = Date.distantPast

    func reset() {
        lock.lock()
        pending.removeAll()
        sequence = 0
        lastLevel = .distantPast
        lock.unlock()
    }

    /// Block für den Mikrofon-Abgriff. Absichtlich außerhalb des Main-Actors gebaut: Er läuft
    /// auf dem Audio-Thread und darf nicht als Main-Actor-Code gelten.
    static func tapBlock(
        converter: AVAudioConverter,
        target: AVAudioFormat,
        packer: LiveFramePacker,
        socket: SocketIOClient,
        level: @escaping @Sendable (Double) -> Void
    ) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            let samples = LiveFramePacker.convert(buffer, with: converter, to: target)
            for frame in packer.push(samples) {
                socket.emitBinary("live-audio", frame)
            }
            if packer.levelDue() {
                level(LiveFramePacker.rms(buffer))
            }
        }
    }

    /// Pegel höchstens etwa zwölfmal pro Sekunde an die Anzeige geben.
    func levelDue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(lastLevel) > 0.08 else { return false }
        lastLevel = now
        return true
    }

    /// Neue Abtastwerte anhängen und volle Rahmen zurückgeben.
    func push(_ samples: [Int16]) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        pending.append(contentsOf: samples)
        var frames: [Data] = []
        while pending.count >= LiveFramePacker.frameSamples {
            let chunk = Array(pending.prefix(LiveFramePacker.frameSamples))
            pending.removeFirst(LiveFramePacker.frameSamples)
            frames.append(LiveFramePacker.pack(sequence: sequence, samples: chunk))
            sequence &+= 1
        }
        // Nicht unbegrenzt puffern, falls die Verbindung hängt.
        if pending.count > LiveFramePacker.frameSamples * 10 { pending.removeAll() }
        return frames
    }

    static func pack(sequence: UInt32, samples: [Int16]) -> Data {
        var data = Data(capacity: 8 + samples.count * 2)
        withUnsafeBytes(of: sequence.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: sampleRate.littleEndian) { data.append(contentsOf: $0) }
        for sample in samples {
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> [Int16] {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return [] }
        let delivered = DeliveredFlag()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if delivered.value {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered.value = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, let channel = output.int16ChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }

    static func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength))
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return Double(sqrt(sum / Float(samples.count)))
    }
}

/// Merkt sich, ob der Konverter den Puffer schon bekommen hat (Klasse statt var, damit der Block nichts Veränderliches einfängt).
final class DeliveredFlag {
    var value = false
}

/// Live-Voice in der Sprach-Ansicht: großer Knopf, Laufzeit, Pegel, Zustand des Widgets.
struct LiveVoicePanel: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let voice = session.liveVoice
        let live = voice.phase == .live
        Plate(title: "Live-Voice", tone: Palette.red, lit: live) {
            if let started = voice.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(clock(from: started, to: context.date))
                        .font(.numeric(14))
                        .foregroundStyle(Palette.red)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    Button {
                        Task { await voice.toggle() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(live ? Palette.red : Palette.surface2)
                                .frame(width: 72, height: 72)
                                .shadow(color: live ? Palette.red.opacity(0.55) : .clear, radius: 14)
                            Circle()
                                .strokeBorder(live ? Color.white.opacity(0.5) : Palette.lineStrong, lineWidth: 2)
                                .frame(width: 72, height: 72)
                            if voice.phase == .preparing {
                                ProgressView().tint(Palette.text)
                            } else {
                                Image(systemName: live ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(live ? .white : Palette.text)
                            }
                        }
                    }
                    .buttonStyle(PadPressStyle())
                    .disabled(!session.can(.liveVoice) || session.isDemo)
                    .accessibilityLabel(live ? "Live-Voice beenden" : "Live-Voice starten")
                    .accessibilityIdentifier("live-voice-button")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(live ? "Du bist live" : (voice.phase == .preparing ? "Startet …" : "Mikrofon aus"))
                            .font(.headline)
                            .foregroundStyle(live ? Palette.red : Palette.text)
                        Text(voice.statusText)
                            .font(.footnote)
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        LevelMeter(level: live ? voice.level : 0)
                            .frame(height: 6)
                    }
                }
                if let error = voice.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.orange)
                }
                if session.isDemo {
                    Text("Live-Voice braucht dein Dashboard; in der Demo ist es aus.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSubtle)
                } else if !live {
                    Text("Deine Stimme geht über den Alert-Dienst ins OBS-Widget. Kopfhörer vermeiden Echo, wenn du den Stream hier mithörst.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func clock(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Pegel als Balken mit Segmenten.
struct LevelMeter: View {
    var level: Double

    var body: some View {
        GeometryReader { geometry in
            let segments = 18
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { index in
                    let threshold = Double(index) / Double(segments)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(level > threshold ? color(for: index, of: segments) : Palette.surface2)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(.linear(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }

    private func color(for index: Int, of count: Int) -> Color {
        let position = Double(index) / Double(count)
        if position > 0.8 { return Palette.red }
        if position > 0.6 { return Palette.amber }
        return Palette.green
    }
}
