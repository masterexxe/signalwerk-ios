import Foundation

// Antworten von /api/app/v1 im Dashboard. Zeitpunkte kommen als ISO-Text (mit Millisekunden)
// und bleiben Text; `SignalwerkDate.parse` macht bei Bedarf ein Datum daraus.

// MARK: - Anmeldung

public struct UserInfo: Codable, Equatable, Hashable {
    public let id: String
    public let name: String?
    public let email: String?
    public let role: String
    public let twitchLogin: String?

    public init(id: String, name: String?, email: String?, role: String, twitchLogin: String?) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.twitchLogin = twitchLogin
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let email, !email.isEmpty { return email }
        if let twitchLogin, !twitchLogin.isEmpty { return twitchLogin }
        return "Unbekannt"
    }

    public var roleLabel: String {
        switch role {
        case "owner": return "Owner"
        case "admin": return "Admin"
        case "moderator": return "Moderator"
        default: return role
        }
    }
}

public struct DevicePushPrefs: Codable, Equatable, Hashable {
    public let queue: Bool
    public init(queue: Bool) { self.queue = queue }
}

public struct DevicePush: Codable, Equatable, Hashable {
    public let environment: String
    public let prefs: DevicePushPrefs
    public init(environment: String, prefs: DevicePushPrefs) {
        self.environment = environment
        self.prefs = prefs
    }
}

public struct DeviceInfo: Codable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let platform: String
    public let createdAt: String
    public let lastSeenAt: String
    public let push: DevicePush?
    /// Nur in der Geräteliste: gehört das Gerät dem angemeldeten Nutzer?
    public let own: Bool?

    public init(id: String, name: String, platform: String, createdAt: String, lastSeenAt: String, push: DevicePush?, own: Bool?) {
        self.id = id
        self.name = name
        self.platform = platform
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.push = push
        self.own = own
    }
}

public struct ServerFeatures: Codable, Equatable, Hashable {
    public let chat: Bool
    public let push: Bool
    public init(chat: Bool, push: Bool) {
        self.chat = chat
        self.push = push
    }
}

public struct ServerInfo: Codable, Equatable, Hashable {
    public let release: String
    public let api: Int
    public let origin: String
    public let socketUrl: String
    public let features: ServerFeatures

    public init(release: String, api: Int, origin: String, socketUrl: String, features: ServerFeatures) {
        self.release = release
        self.api = api
        self.origin = origin
        self.socketUrl = socketUrl
        self.features = features
    }
}

/// Antwort nach der Anmeldung: Token für dieses Gerät und alles, was die App braucht.
public struct SessionPayload: Codable, Equatable {
    public let token: String
    public let user: UserInfo
    public let permissions: [String]
    public let device: DeviceInfo
    public let server: ServerInfo
}

public struct MeResponse: Codable, Equatable {
    public let user: UserInfo
    public let permissions: [String]
    public let device: DeviceInfo
    public let server: ServerInfo

    public init(user: UserInfo, permissions: [String], device: DeviceInfo, server: ServerInfo) {
        self.user = user
        self.permissions = permissions
        self.device = device
        self.server = server
    }
}

/// Rechte wie im Dashboard (lib/authz.ts).
public enum Permission: String {
    case moderateDonations = "donation.moderate"
    case playSounds = "sound.play"
    case stopAlerts = "alerts.stop"
    case sendTTS = "tts.send"
    case reloadWidget = "widget.reload"
    case liveVoice = "livevoice.start"
    case moderateChat = "chat.moderate"
    case manageUsers = "user.manage"
}

// MARK: - Übersicht

public struct NameAmount: Codable, Equatable, Hashable {
    public let name: String
    public let amount: String
    public init(name: String, amount: String) {
        self.name = name
        self.amount = amount
    }
}

public struct LastDonation: Codable, Equatable, Hashable {
    public let name: String
    public let amount: String
    public let at: String
    public init(name: String, amount: String, at: String) {
        self.name = name
        self.amount = amount
        self.at = at
    }
}

public struct DashboardStats: Codable, Equatable, Hashable {
    public let todayCount: Int
    public let todaySumLabel: String
    public let totalCount: Int
    public let pendingDonations: Int
    public let pendingSubBombs: Int
    public let todayTop: NameAmount?
    public let lastDonation: LastDonation?
    public let todaySubBombs: Int
    public let todayGiftedSubs: Int

    public init(todayCount: Int, todaySumLabel: String, totalCount: Int, pendingDonations: Int, pendingSubBombs: Int, todayTop: NameAmount?, lastDonation: LastDonation?, todaySubBombs: Int, todayGiftedSubs: Int) {
        self.todayCount = todayCount
        self.todaySumLabel = todaySumLabel
        self.totalCount = totalCount
        self.pendingDonations = pendingDonations
        self.pendingSubBombs = pendingSubBombs
        self.todayTop = todayTop
        self.lastDonation = lastDonation
        self.todaySubBombs = todaySubBombs
        self.todayGiftedSubs = todayGiftedSubs
    }
}

public struct PendingCounts: Codable, Equatable, Hashable {
    public let donations: Int
    public let subBombs: Int
    public init(donations: Int, subBombs: Int) {
        self.donations = donations
        self.subBombs = subBombs
    }

    public var total: Int { donations + subBombs }
}

/// Minutenwerte eines Streams: Zeit (ms seit 1970), Zuschauer, Chatter.
public struct StreamSeries: Codable, Equatable, Hashable {
    public let times: [Double]
    public let viewers: [Int]
    public let chatters: [Int]

    public init(times: [Double], viewers: [Int], chatters: [Int]) {
        self.times = times
        self.viewers = viewers
        self.chatters = chatters
    }

    public struct Point: Identifiable, Hashable {
        public let date: Date
        public let viewers: Int
        public let chatters: Int
        public var id: Double { date.timeIntervalSince1970 }
    }

    public var points: [Point] {
        let count = min(times.count, viewers.count, chatters.count)
        return (0..<count).map { index in
            Point(date: Date(timeIntervalSince1970: times[index] / 1000), viewers: viewers[index], chatters: chatters[index])
        }
    }
}

public struct StreamSummary: Codable, Equatable, Hashable {
    public let login: String
    public let live: Bool
    public let title: String
    public let category: String
    public let startedAt: String?
    public let viewers: Int
    public let chatters: Int
    public let peak: Int
    public let average: Int
    public let series: StreamSeries

    public init(login: String, live: Bool, title: String, category: String, startedAt: String?, viewers: Int, chatters: Int, peak: Int, average: Int, series: StreamSeries) {
        self.login = login
        self.live = live
        self.title = title
        self.category = category
        self.startedAt = startedAt
        self.viewers = viewers
        self.chatters = chatters
        self.peak = peak
        self.average = average
        self.series = series
    }
}

public struct WidgetCounts: Codable, Equatable, Hashable {
    public let count: Int
    public let outdated: Int
    public init(count: Int, outdated: Int) {
        self.count = count
        self.outdated = outdated
    }
}

public struct LiveVoiceStatus: Codable, Equatable, Hashable {
    public let active: Bool
    public let viewers: Int
    public init(active: Bool, viewers: Int) {
        self.active = active
        self.viewers = viewers
    }
}

public struct SystemSummary: Codable, Equatable, Hashable {
    public let alertsReachable: Bool
    public let alertsVersion: String
    /// "connected", "connecting", "disabled" oder "unknown".
    public let streamlabs: String
    /// "elevenlabs" oder "mock".
    public let tts: String
    public let widgets: WidgetCounts?
    public let liveVoice: LiveVoiceStatus?
    public let lastAlertAt: String?
    public let lastStopAt: String?

    public init(alertsReachable: Bool, alertsVersion: String, streamlabs: String, tts: String, widgets: WidgetCounts?, liveVoice: LiveVoiceStatus?, lastAlertAt: String?, lastStopAt: String?) {
        self.alertsReachable = alertsReachable
        self.alertsVersion = alertsVersion
        self.streamlabs = streamlabs
        self.tts = tts
        self.widgets = widgets
        self.liveVoice = liveVoice
        self.lastAlertAt = lastAlertAt
        self.lastStopAt = lastStopAt
    }
}

public struct Channel: Codable, Equatable, Hashable, Identifiable {
    public let login: String
    public let displayName: String
    public let own: Bool
    public var id: String { login }
    public init(login: String, displayName: String, own: Bool) {
        self.login = login
        self.displayName = displayName
        self.own = own
    }
}

public struct ChannelsResponse: Codable, Equatable, Hashable {
    public let defaultLogin: String
    public let channels: [Channel]
    public init(defaultLogin: String, channels: [Channel]) {
        self.defaultLogin = defaultLogin
        self.channels = channels
    }
}

public struct Overview: Codable, Equatable {
    public let at: String
    public let stats: DashboardStats
    public let pending: PendingCounts
    public let stream: StreamSummary?
    public let system: SystemSummary
    public let channels: ChannelsResponse

    public init(at: String, stats: DashboardStats, pending: PendingCounts, stream: StreamSummary?, system: SystemSummary, channels: ChannelsResponse) {
        self.at = at
        self.stats = stats
        self.pending = pending
        self.stream = stream
        self.system = system
        self.channels = channels
    }
}

// MARK: - Spenden und Sub-Bombs

public enum QueueFilter: String, CaseIterable, Identifiable {
    case open
    case all
    public var id: String { rawValue }
}

public enum QueueAction: String {
    case accept
    case block
    case replay
}

public struct QueueItem: Codable, Equatable, Hashable, Identifiable {
    /// "donation" oder "subbomb".
    public let kind: String
    public let id: String
    public let name: String
    public let message: String
    /// Spende: Betrag wie "10,00 €"; Sub-Bomb: Anzahl der Abos.
    public let amount: String
    public let voice: String
    /// "pending", "accepted" oder "blocked".
    public var state: String
    public let at: String

    public init(kind: String, id: String, name: String, message: String, amount: String, voice: String, state: String, at: String) {
        self.kind = kind
        self.id = id
        self.name = name
        self.message = message
        self.amount = amount
        self.voice = voice
        self.state = state
        self.at = at
    }

    public var key: String { "\(kind):\(id)" }
    public var isSubBomb: Bool { kind == "subbomb" }
    public var isPending: Bool { state == "pending" }
    public var isAccepted: Bool { state == "accepted" }
    public var isBlocked: Bool { state == "blocked" }

    /// Betrag zum Anzeigen: Spenden wie geliefert, Sub-Bombs als "12 Abos".
    public var amountLabel: String {
        guard isSubBomb else { return amount }
        let count = Int(amount.trimmingCharacters(in: .whitespaces)) ?? 0
        return count == 1 ? "1 Abo" : "\(amount) Abos"
    }

    public var date: Date? { SignalwerkDate.parse(at) }
}

public struct QueueResponse: Codable, Equatable {
    public let filter: String
    public let items: [QueueItem]
    public let pending: PendingCounts
    public init(filter: String, items: [QueueItem], pending: PendingCounts) {
        self.filter = filter
        self.items = items
        self.pending = pending
    }

    /// Ein Satz für Siri und Kurzbefehle: was wartet, und was als Nächstes kommt.
    public var spokenSummary: String {
        let donations = pending.donations
        let bombs = pending.subBombs
        guard donations + bombs > 0 else { return "Nichts offen, die Warteschlange ist leer." }
        var parts: [String] = []
        if donations > 0 { parts.append(donations == 1 ? "1 Spende" : "\(donations) Spenden") }
        if bombs > 0 { parts.append(bombs == 1 ? "1 Sub-Bomb" : "\(bombs) Sub-Bombs") }
        var text = parts.joined(separator: " und ") + (donations + bombs == 1 ? " wartet." : " warten.")
        if let next = items.first(where: { $0.isPending }) {
            text += " Als Nächstes: \(next.name) mit \(next.amountLabel)."
        }
        return text
    }
}

// MARK: - Sounds und Sprache

public struct Sound: Codable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let volume: Int
    public let previewUrl: String
    public init(id: String, name: String, volume: Int, previewUrl: String) {
        self.id = id
        self.name = name
        self.volume = volume
        self.previewUrl = previewUrl
    }
}

public struct SoundsResponse: Codable, Equatable {
    public let master: Int
    public let sounds: [Sound]
    public init(master: Int, sounds: [Sound]) {
        self.master = master
        self.sounds = sounds
    }
}

public struct Voice: Codable, Equatable, Hashable, Identifiable {
    /// Wert für die TTS: "default" oder der Name der Stimme in Kleinbuchstaben.
    public let value: String
    public let name: String
    public let speed: Double?
    public var id: String { value }
    public init(value: String, name: String, speed: Double?) {
        self.value = value
        self.name = name
        self.speed = speed
    }
}

public struct VoicesResponse: Codable, Equatable {
    public let voices: [Voice]
    public init(voices: [Voice]) { self.voices = voices }
}

// MARK: - Aktionen

/// Ergebnis einer Aktion. `warning` zeigt die App als Hinweis (etwa "Kein OBS-Widget verbunden").
public struct ActionOutcome: Equatable {
    public let warning: String?
    public init(warning: String? = nil) { self.warning = warning }
}

/// Hülle der Aktionsantworten: { ok, data, warning } oder { ok: false, error }.
public struct ActionReply<T: Decodable>: Decodable {
    public let ok: Bool
    public let data: T?
    public let warning: String?
    public let error: String?
}

/// Platzhalter, wenn die Daten einer Aktion egal sind.
public struct Ignored: Codable, Equatable {
    public init() {}
}

public struct StopResult: Codable, Equatable {
    public let widgets: Int
    public let outdated: Int
}

public struct ChatTicket: Codable, Equatable {
    public let token: String
    public let socketUrl: String
    public init(token: String, socketUrl: String) {
        self.token = token
        self.socketUrl = socketUrl
    }
}

public struct LiveVoiceSession: Codable, Equatable {
    public let token: String
    public let resumeDelayMs: Int
    public let stunUrls: [String]
    public let socketUrl: String
    public init(token: String, resumeDelayMs: Int, stunUrls: [String], socketUrl: String) {
        self.token = token
        self.resumeDelayMs = resumeDelayMs
        self.stunUrls = stunUrls
        self.socketUrl = socketUrl
    }
}

public struct ModerationRequest: Equatable {
    /// "delete", "timeout", "ban", "unban" oder "warn".
    public let action: String
    public let channel: String
    public let userId: String
    public let login: String
    public let messageId: String?
    public let seconds: Int?
    public let reason: String?

    public init(action: String, channel: String, userId: String, login: String, messageId: String? = nil, seconds: Int? = nil, reason: String? = nil) {
        self.action = action
        self.channel = channel
        self.userId = userId
        self.login = login
        self.messageId = messageId
        self.seconds = seconds
        self.reason = reason
    }
}

public struct ModerationResult: Codable, Equatable {
    public let text: String
    public let account: String
}

// MARK: - Statistik

public struct StreamSnapshot: Codable, Equatable {
    public let login: String
    public let tracked: Bool
    public let live: Bool
    public let title: String
    public let category: String
    public let startedAt: String?
    public let endedAt: String?
    public let times: [Double]
    public let viewers: [Int]
    public let chatters: [Int]
    public let peak: Int
    public let average: Int
    public let uniqueChatters: Int

    public init(login: String, tracked: Bool, live: Bool, title: String, category: String, startedAt: String?, endedAt: String?, times: [Double], viewers: [Int], chatters: [Int], peak: Int, average: Int, uniqueChatters: Int) {
        self.login = login
        self.tracked = tracked
        self.live = live
        self.title = title
        self.category = category
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.times = times
        self.viewers = viewers
        self.chatters = chatters
        self.peak = peak
        self.average = average
        self.uniqueChatters = uniqueChatters
    }

    public var series: StreamSeries { StreamSeries(times: times, viewers: viewers, chatters: chatters) }
}

// MARK: - Geräte

public struct DevicesResponse: Codable, Equatable {
    public let current: String
    public let devices: [DeviceInfo]
    public init(current: String, devices: [DeviceInfo]) {
        self.current = current
        self.devices = devices
    }
}

// MARK: - Live-Ereignisse

/// Ereignis aus /api/app/v1/events ("ready", "refresh", "revoked").
public struct ServerEvent: Equatable {
    public let name: String
    public let data: String
    public init(name: String, data: String) {
        self.name = name
        self.data = data
    }
}
