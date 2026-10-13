import Foundation

/// Stücke einer Chat-Nachricht für die Anzeige (wie segmentsOf im Dashboard).
public enum ChatSegment: Equatable, Hashable {
    case text(String)
    case emote(name: String, url: String, url2: String, provider: String)
    case mention(text: String, login: String)
    case link(text: String, href: String)
}

public enum ChatText {
    /// Bild eines Twitch-Emotes ("default" nimmt die animierte Fassung, wenn es eine gibt).
    public static func twitchEmoteURL(_ id: String, scale: String = "1.0") -> String {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return "https://static-cdn.jtvnw.net/emoticons/v2/\(encoded)/default/dark/\(scale)"
    }

    private static let tlds: Set<String> = ["com", "de", "net", "org", "tv", "gg", "io", "me", "ly", "co", "at", "ch", "eu", "info", "xyz", "app", "link"]

    /// Text mit Twitch-Emotes (Positionen in Codepoints) und Emotes von 7TV/BTTV/FFZ nach Namen.
    public static func segments(_ text: String, emotes: [ChatEmote], extra: [String: ChatExtraEmote] = [:]) -> [ChatSegment] {
        var out: [ChatSegment] = []
        let scalars = Array(text.unicodeScalars)
        var cursor = 0
        for emote in emotes.sorted(by: { $0.start < $1.start }) {
            guard emote.start >= cursor, emote.end < scalars.count, emote.start <= emote.end else { continue }
            splitWords(&out, string(scalars[cursor..<emote.start]), extra: extra)
            let name = string(scalars[emote.start...emote.end])
            out.append(.emote(name: name, url: twitchEmoteURL(emote.id), url2: twitchEmoteURL(emote.id, scale: "2.0"), provider: "twitch"))
            cursor = emote.end + 1
        }
        if cursor < scalars.count {
            splitWords(&out, string(scalars[cursor...]), extra: extra)
        }
        return out
    }

    /// Erwähnt der Text diesen Login (mit oder ohne @)?
    public static func mentions(_ text: String, login: String) -> Bool {
        let needle = login.lowercased()
        guard !needle.isEmpty else { return false }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.!?:;"))
        return text.lowercased().components(separatedBy: separators).contains { $0 == needle || $0 == "@" + needle }
    }

    private static func string(_ slice: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: slice)
        return String(view)
    }

    private static func pushText(_ out: inout [ChatSegment], _ text: String) {
        guard !text.isEmpty else { return }
        if case .text(let previous)? = out.last {
            out[out.count - 1] = .text(previous + text)
        } else {
            out.append(.text(text))
        }
    }

    /// Wörter mit den Leerzeichen dazwischen, damit nichts verloren geht.
    private static func tokens(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var currentIsSpace: Bool?
        for character in text {
            let isSpace = character.isWhitespace
            if let state = currentIsSpace, state != isSpace {
                parts.append(current)
                current = ""
            }
            current.append(character)
            currentIsSpace = isSpace
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    private static func splitWords(_ out: inout [ChatSegment], _ text: String, extra: [String: ChatExtraEmote]) {
        for part in tokens(text) {
            if part.first?.isWhitespace == true {
                pushText(&out, part)
                continue
            }
            if let emote = extra[part] {
                out.append(.emote(name: part, url: emote.url, url2: emote.url2, provider: emote.provider))
                continue
            }
            if let href = link(part) {
                out.append(.link(text: part, href: href))
                continue
            }
            if let found = mention(part) {
                out.append(.mention(text: "@" + found.login, login: found.login.lowercased()))
                pushText(&out, found.trailing)
                continue
            }
            pushText(&out, part)
        }
    }

    static func link(_ word: String) -> String? {
        let lower = word.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return word.count > 8 && !word.contains("\"") && !word.contains("<") ? word : nil
        }
        // example.de oder example.de/pfad
        let hostPart = lower.split(separator: "/", maxSplits: 1).first.map(String.init) ?? lower
        let labels = hostPart.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.count >= 2, let tld = labels.last, tlds.contains(tld) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        for label in labels.dropLast() {
            guard !label.isEmpty, label.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }) else { return nil }
        }
        return "https://" + word
    }

    static func mention(_ word: String) -> (login: String, trailing: String)? {
        guard word.hasPrefix("@") else { return nil }
        let body = word.dropFirst()
        let login = body.prefix(while: { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
        let trailing = body.dropFirst(login.count)
        guard (3...25).contains(login.count), trailing.allSatisfy({ ",.!?:;".contains($0) }) else { return nil }
        return (login: String(login), trailing: String(trailing))
    }
}
