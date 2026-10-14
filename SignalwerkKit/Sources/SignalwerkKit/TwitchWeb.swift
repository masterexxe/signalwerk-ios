import Foundation

/// Twitch im Player der App: Adresse des Players und Anmeldung über die Cookies von twitch.tv.
///
/// Der Player läuft als eigene Seite auf player.twitch.tv (wie das Popout-Fenster von Twitch),
/// nicht eingebettet in eine fremde Seite. Eingebettet bekäme er unter iOS keine Cookies von
/// twitch.tv, wüsste nichts von der Anmeldung und spielte Werbung wie für Gäste.
public enum TwitchWeb {
    public static let playerHost = "player.twitch.tv"
    public static let loginURL = URL(string: "https://www.twitch.tv/login")!

    /// Player eines Kanals; `parent=twitch.tv` wie beim Popout-Player von Twitch.
    public static func playerURL(channel: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = playerHost
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "channel", value: channel.trimmingCharacters(in: .whitespaces).lowercased()),
            URLQueryItem(name: "parent", value: "twitch.tv"),
            URLQueryItem(name: "autoplay", value: "true"),
            URLQueryItem(name: "muted", value: "false"),
        ]
        return components.url!
    }

    /// Gehört der Host (oder die Cookie-Domain) zu twitch.tv – www, m, id, player …?
    public static func isTwitch(host: String?) -> Bool {
        guard var host = host?.lowercased() else { return false }
        while host.hasPrefix(".") { host.removeFirst() }
        return host == "twitch.tv" || host.hasSuffix(".twitch.tv")
    }

    public static func isPlayer(host: String?) -> Bool {
        host?.lowercased() == playerHost
    }

    /// Ende der Browserkennung wie bei Safari, damit twitch.tv die Web-Ansicht wie Safari behandelt:
    /// iPhone "Version/26.0 Mobile/15E148 Safari/604.1", iPad (Desktop-Seiten) "Version/26.0 Safari/605.1.15".
    public static func userAgentSuffix(systemVersion: String, pad: Bool) -> String {
        let parts = systemVersion.split(separator: ".").map(String.init)
        let major = parts.first.flatMap { Int($0) } ?? 17
        let minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        let version = "Version/\(major).\(minor)"
        return pad ? "\(version) Safari/605.1.15" : "\(version) Mobile/15E148 Safari/604.1"
    }

    /// Angemeldetes Konto aus den Cookies von twitch.tv; nil, wenn niemand angemeldet ist.
    /// Angemeldet heißt: Cookie `auth-token`. Den Namen liefern `twilight-user` (JSON) oder `login`.
    public static func account(from cookies: [WebCookie]) -> TwitchWebAccount? {
        let twitch = cookies.filter { isTwitch(host: $0.domain) }
        func value(_ name: String) -> String? {
            let found = twitch.first(where: { $0.name == name && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty })
            return found?.value.trimmingCharacters(in: .whitespaces)
        }
        guard value("auth-token") != nil else { return nil }
        let user = value("twilight-user").flatMap { decodeUser($0) }
        let login = value("login") ?? user?.login ?? value("name") ?? ""
        let displayName = user?.displayName ?? ""
        return TwitchWebAccount(login: login, displayName: displayName.isEmpty ? login : displayName)
    }

    private struct TwilightUser: Decodable {
        let login: String?
        let displayName: String?
    }

    private static func decodeUser(_ raw: String) -> TwilightUser? {
        let text = raw.removingPercentEncoding ?? raw
        return try? JSONDecoder().decode(TwilightUser.self, from: Data(text.utf8))
    }
}

/// Ein Cookie, wie ihn die Web-Ansicht liefert (nur, was der Kern braucht).
public struct WebCookie: Equatable, Sendable {
    public let name: String
    public let value: String
    public let domain: String

    public init(name: String, value: String, domain: String) {
        self.name = name
        self.value = value
        self.domain = domain
    }
}

/// Bei Twitch angemeldetes Konto im Player.
public struct TwitchWebAccount: Equatable, Sendable {
    public let login: String
    public let displayName: String

    public init(login: String, displayName: String) {
        self.login = login
        self.displayName = displayName
    }

    /// Für die Anzeige.
    public var label: String {
        if !displayName.isEmpty { return displayName }
        return login.isEmpty ? "Twitch-Konto" : login
    }
}
