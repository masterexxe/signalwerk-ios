import Foundation

/// Signalwerk ohne Server: feste Beispieldaten, Aktionen ändern nur den Zustand in der App.
/// Für "Demo ansehen", für Vorschauen und für die UI-Tests (Screenshots auf iPhone und iPad).
public final class DemoBackend: SignalwerkBackend {
    public var isDemo: Bool { true }
    public let serverURL = URL(string: "https://demo.signalwerk.live")!

    /// Neue Spenden von selbst (für die Demo in der App). In Tests aus.
    public let simulateLive: Bool
    private let lock = NSLock()
    private var items: [QueueItem]
    private var deviceList: [DeviceInfo]
    private var counter = 0
    private let start: Date
    private var listeners: [UUID: AsyncThrowingStream<ServerEvent, Error>.Continuation] = [:]
    private var timer: Timer?

    public init(simulateLive: Bool = false, now: Date = Date()) {
        self.simulateLive = simulateLive
        self.start = now
        self.items = DemoBackend.makeQueue(now: now)
        self.deviceList = [
            DeviceInfo(id: "demoipad000000000001", name: "iPad Pro", platform: "ipados", createdAt: SignalwerkDate.string(now.addingTimeInterval(-86400 * 3)), lastSeenAt: SignalwerkDate.string(now), push: DevicePush(environment: "production", prefs: DevicePushPrefs(queue: true)), own: true),
            DeviceInfo(id: "demoiphone0000000002", name: "iPhone", platform: "ios", createdAt: SignalwerkDate.string(now.addingTimeInterval(-86400 * 9)), lastSeenAt: SignalwerkDate.string(now.addingTimeInterval(-3600 * 5)), push: nil, own: true),
        ]
    }

    deinit {
        timer?.invalidate()
    }

    public static let user = UserInfo(id: "demo", name: "Demo", email: "demo@signalwerk.live", role: "owner", twitchLogin: nil)
    public static let permissions = [
        "donation.moderate", "sound.play", "alerts.stop", "tts.send", "widget.reload", "livevoice.start", "chat.moderate", "user.manage",
    ]
    public static let server = ServerInfo(release: "2.5.0", api: 1, origin: "https://demo.signalwerk.live", socketUrl: "https://demo.signalwerk.live", features: ServerFeatures(chat: true, push: true))
    public static let channelsResponse = ChannelsResponse(defaultLogin: "signalwerk_live", channels: [
        Channel(login: "signalwerk_live", displayName: "Signalwerk Live", own: true),
        Channel(login: "gastshow", displayName: "Gastshow", own: false),
    ])

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: - Daten

    static func makeQueue(now: Date) -> [QueueItem] {
        func at(_ minutesAgo: Double) -> String { SignalwerkDate.string(now.addingTimeInterval(-minutesAgo * 60)) }
        return [
            QueueItem(kind: "donation", id: "d-1001", name: "MaxPower", message: "Grüße aus Hamburg, macht weiter so! Der Drop vorhin war unfassbar.", amount: "25,00 €", voice: "echo", state: "pending", at: at(1)),
            QueueItem(kind: "subbomb", id: "s-2001", name: "Lea_K", message: "", amount: "10", voice: "default", state: "pending", at: at(3)),
            QueueItem(kind: "donation", id: "d-1002", name: "ByteWolf", message: "Für den neuen Kamera-Arm. Bitte nicht wieder vom Dach fallen lassen 😅", amount: "10,00 €", voice: "default", state: "pending", at: at(6)),
            QueueItem(kind: "donation", id: "d-1003", name: "LunaPxl", message: "Erste Spende überhaupt! Grüße an den Chat.", amount: "5,00 €", voice: "nova", state: "pending", at: at(11)),
            QueueItem(kind: "donation", id: "d-0999", name: "TobiBaut", message: "Danke für den Stream gestern, war mega.", amount: "7,50 €", voice: "default", state: "accepted", at: at(24)),
            QueueItem(kind: "donation", id: "d-0998", name: "Fuchs_Kathi", message: "Musikwunsch: irgendwas mit Trommeln", amount: "3,00 €", voice: "default", state: "accepted", at: at(41)),
            QueueItem(kind: "donation", id: "d-0997", name: "Troll99", message: "kauft follower auf spam.example", amount: "1,00 €", voice: "default", state: "blocked", at: at(52)),
            QueueItem(kind: "subbomb", id: "s-1999", name: "Kai_88", message: "", amount: "5", voice: "default", state: "accepted", at: at(75)),
        ]
    }

    static let soundList: [Sound] = makeSounds()

    private static func makeSounds() -> [Sound] {
        let names = ["Jingle Spenden", "Wow", "Level Up", "Fail Trombone", "Trommelwirbel", "Applaus", "Airhorn", "Sad Violin", "Ding", "Countdown", "Crowd Ooh"]
        let volumes = [100, 90, 100, 80, 100, 100, 70, 100, 100, 100, 100]
        var result: [Sound] = []
        for index in 0..<names.count {
            result.append(Sound(id: "sound-\(index + 1)", name: names[index], volume: volumes[index], previewUrl: "https://demo.signalwerk.live/api/media/sound-\(index + 1)"))
        }
        return result
    }

    static let voiceList: [Voice] = [
        Voice(value: "default", name: "Standard", speed: nil),
        Voice(value: "echo", name: "Echo", speed: nil),
        Voice(value: "nova", name: "Nova", speed: 1.1),
    ]

    /// Zuschauerverlauf der letzten zwei Stunden (eine Messung pro Minute, ruhig schwankend).
    static func series(now: Date, minutes: Int = 120) -> StreamSeries {
        var times: [Double] = []
        var viewers: [Int] = []
        var chatters: [Int] = []
        for minute in 0..<minutes {
            let date = now.addingTimeInterval(Double(minute - minutes + 1) * 60)
            let t = Double(minute)
            let wave = 900 * sin(t / 11) + 420 * sin(t / 3.7) + 260 * cos(t / 23)
            let ramp = min(1, t / 25)
            let value = Int((9800 + 2600 * ramp + wave).rounded())
            times.append(date.timeIntervalSince1970 * 1000)
            viewers.append(value)
            chatters.append(Int(Double(value) * (0.085 + 0.01 * sin(t / 7))))
        }
        return StreamSeries(times: times, viewers: viewers, chatters: chatters)
    }

    // MARK: - SignalwerkBackend

    public func me() async throws -> MeResponse {
        let devices = locked { deviceList }
        return MeResponse(user: DemoBackend.user, permissions: DemoBackend.permissions, device: devices[0], server: DemoBackend.server)
    }

    public func overview() async throws -> Overview {
        let now = Date()
        let snapshot = locked { items }
        let pending = PendingCounts(
            donations: snapshot.filter { $0.isPending && !$0.isSubBomb }.count,
            subBombs: snapshot.filter { $0.isPending && $0.isSubBomb }.count
        )
        let series = DemoBackend.series(now: now)
        let stats = DashboardStats(
            todayCount: 14,
            todaySumLabel: "381,00 €",
            totalCount: 412,
            pendingDonations: pending.donations,
            pendingSubBombs: pending.subBombs,
            todayTop: NameAmount(name: "MaxPower", amount: "100,00 €"),
            lastDonation: snapshot.first(where: { !$0.isSubBomb }).map { LastDonation(name: $0.name, amount: $0.amount, at: $0.at) },
            todaySubBombs: 8,
            todayGiftedSubs: 134
        )
        let stream = StreamSummary(
            login: "signalwerk_live",
            live: true,
            title: "Sonntagsstream mit Gästen – Kamera-Umbau und Q&A",
            category: "Just Chatting",
            startedAt: SignalwerkDate.string(start.addingTimeInterval(-3 * 3600 - 480)),
            viewers: series.viewers.last ?? 0,
            chatters: series.chatters.last ?? 0,
            peak: (series.viewers.max() ?? 0) + 2100,
            average: 10165,
            series: series
        )
        let system = SystemSummary(alertsReachable: true, alertsVersion: "2.5.0", streamlabs: "connected", tts: "elevenlabs", widgets: WidgetCounts(count: 1, outdated: 0), liveVoice: LiveVoiceStatus(active: false, viewers: 0), lastAlertAt: SignalwerkDate.string(now.addingTimeInterval(-300)), lastStopAt: nil)
        return Overview(at: SignalwerkDate.string(now), stats: stats, pending: pending, stream: stream, system: system, channels: DemoBackend.channelsResponse)
    }

    public func queue(filter: QueueFilter) async throws -> QueueResponse {
        let snapshot = locked { items }
        let pending = PendingCounts(
            donations: snapshot.filter { $0.isPending && !$0.isSubBomb }.count,
            subBombs: snapshot.filter { $0.isPending && $0.isSubBomb }.count
        )
        let list = filter == .open ? snapshot.filter(\.isPending) : snapshot
        return QueueResponse(filter: filter.rawValue, items: list, pending: pending)
    }

    public func decide(_ item: QueueItem, action: QueueAction) async throws -> ActionOutcome {
        try await Task.sleep(nanoseconds: 250_000_000)
        let result: Result<ActionOutcome, SignalwerkError> = locked {
            guard let index = items.firstIndex(where: { $0.key == item.key }) else {
                return .failure(.server(status: 404, message: item.isSubBomb ? "Sub-Bomb nicht gefunden." : "Spende nicht gefunden."))
            }
            let current = items[index]
            switch action {
            case .accept, .block:
                if current.isBlocked {
                    return .failure(.server(status: 400, message: current.isSubBomb ? "Blockierte Sub-Bombs können nicht geändert werden." : "Blockierte Spenden können nicht geändert werden."))
                }
                items[index].state = action == .accept ? "accepted" : "blocked"
                return .success(ActionOutcome())
            case .replay:
                guard current.isAccepted else {
                    return .failure(.server(status: 400, message: "Nur angenommene Spenden lassen sich wiederholen."))
                }
                return .success(ActionOutcome())
            }
        }
        broadcast("refresh")
        return try result.get()
    }

    public func sounds() async throws -> SoundsResponse {
        SoundsResponse(master: 85, sounds: DemoBackend.soundList)
    }

    public func playSound(id: String) async throws -> ActionOutcome {
        try await Task.sleep(nanoseconds: 120_000_000)
        guard DemoBackend.soundList.contains(where: { $0.id == id }) else {
            throw SignalwerkError.server(status: 400, message: "Sound nicht verfügbar.")
        }
        return ActionOutcome()
    }

    public func voices() async throws -> [Voice] {
        DemoBackend.voiceList
    }

    public func speak(text: String, voice: String, speed: Double?) async throws -> ActionOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw SignalwerkError.server(status: 400, message: "Kein Text.") }
        if trimmed.count > 500 { throw SignalwerkError.server(status: 400, message: "Höchstens 500 Zeichen.") }
        try await Task.sleep(nanoseconds: 300_000_000)
        return ActionOutcome()
    }

    public func emergencyStop() async throws -> ActionOutcome {
        try await Task.sleep(nanoseconds: 150_000_000)
        return ActionOutcome()
    }

    public func testAlert() async throws -> ActionOutcome {
        ActionOutcome()
    }

    public func reloadWidget() async throws -> ActionOutcome {
        ActionOutcome()
    }

    public func channels() async throws -> ChannelsResponse {
        DemoBackend.channelsResponse
    }

    public func stream(login: String?) async throws -> StreamSnapshot {
        let series = DemoBackend.series(now: Date())
        return StreamSnapshot(
            login: login ?? "signalwerk_live",
            tracked: true,
            live: true,
            title: "Sonntagsstream mit Gästen – Kamera-Umbau und Q&A",
            category: "Just Chatting",
            startedAt: SignalwerkDate.string(start.addingTimeInterval(-3 * 3600 - 480)),
            endedAt: nil,
            times: series.times,
            viewers: series.viewers,
            chatters: series.chatters,
            peak: (series.viewers.max() ?? 0) + 2100,
            average: 10165,
            uniqueChatters: 1054
        )
    }

    public func chatTicket() async throws -> ChatTicket {
        ChatTicket(token: "demo", socketUrl: serverURL.absoluteString)
    }

    public func sendChat(channel: String, text: String, replyTo: String?) async throws -> ActionOutcome {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            throw SignalwerkError.server(status: 400, message: "Nachricht leer oder länger als 500 Zeichen.")
        }
        return ActionOutcome()
    }

    public func moderate(_ request: ModerationRequest) async throws -> String {
        switch request.action {
        case "timeout": return "Timeout für \(request.login): \(SignalwerkFormat.timeout(request.seconds ?? 600))."
        case "ban": return "\(request.login) gebannt."
        case "unban": return "Timeout/Bann für \(request.login) aufgehoben."
        case "delete": return "Nachricht gelöscht."
        default: return "Erledigt."
        }
    }

    public func openLiveVoice() async throws -> LiveVoiceSession {
        throw SignalwerkError.server(status: 400, message: "Live-Voice gibt es in der Demo nicht.")
    }

    public func devices() async throws -> DevicesResponse {
        let devices = locked { deviceList }
        return DevicesResponse(current: devices.first?.id ?? "", devices: devices)
    }

    public func revokeDevice(id: String) async throws {
        locked { deviceList.removeAll { $0.id == id } }
    }

    public func registerPush(token: String?, environment: String, queue: Bool) async throws {}

    public func testPush() async throws {
        throw SignalwerkError.server(status: 400, message: "In der Demo gibt es keine Mitteilungen.")
    }

    public func logout() async throws {}

    public func events() -> AsyncThrowingStream<ServerEvent, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            self.locked { self.listeners[id] = continuation }
            continuation.yield(ServerEvent(name: "ready", data: "{}"))
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.locked { _ = self.listeners.removeValue(forKey: id) }
            }
            if self.simulateLive { self.startSimulation() }
        }
    }

    // MARK: - Simulation

    private func broadcast(_ name: String) {
        let targets = locked { Array(listeners.values) }
        for continuation in targets { continuation.yield(ServerEvent(name: name, data: "{}")) }
    }

    private func startSimulation() {
        DispatchQueue.main.async {
            guard self.timer == nil else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: 40, repeats: true) { [weak self] _ in
                self?.addDemoDonation()
            }
        }
    }

    private static let samples: [(String, String, String)] = [
        ("Neuling", "Bin über den Raid hier, richtig cooler Stream!", "2,00 €"),
        ("MiraMC", "Für die Kaffeekasse ☕", "4,20 €"),
        ("Kai_88", "Wann kommt das nächste Event?", "15,00 €"),
        ("ByteWolf", "Noch eine Runde Trommelwirbel bitte", "6,00 €"),
    ]

    func addDemoDonation() {
        locked {
            counter += 1
            let sample = DemoBackend.samples[counter % DemoBackend.samples.count]
            items.insert(QueueItem(kind: "donation", id: "d-live-\(counter)", name: sample.0, message: sample.1, amount: sample.2, voice: "default", state: "pending", at: SignalwerkDate.string(Date())), at: 0)
        }
        broadcast("refresh")
    }
}
