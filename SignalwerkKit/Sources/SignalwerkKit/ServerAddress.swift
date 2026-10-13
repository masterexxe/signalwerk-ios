import Foundation

/// Adresse des Dashboards aus der Eingabe in der App.
///
/// "dashboard.signalwerk.live" → https://dashboard.signalwerk.live. Ein ausdrückliches
/// http:// bleibt (lokale Tests). Pfade, Query und Schrägstriche am Ende fallen weg.
public enum ServerAddress {
    public static let suggested = "dashboard.signalwerk.live"

    public static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if let marker = text.range(of: "://") {
            // Ausdrückliches Schema: nur http und https.
            let scheme = text[..<marker.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
        } else {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.host = host.lowercased()
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    /// Für die Anzeige: ohne https://.
    public static func display(_ url: URL) -> String {
        var text = url.absoluteString
        if text.hasPrefix("https://") { text.removeFirst("https://".count) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
