import Foundation

/// ISO-Zeitpunkte aus dem Dashboard ("2026-10-13T11:01:05.106Z", mit oder ohne Millisekunden).
public enum SignalwerkDate {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return withFraction.date(from: text) ?? plain.date(from: text)
    }

    public static func string(_ date: Date) -> String {
        withFraction.string(from: date)
    }
}

/// Texte für Zahlen und Zeiten, deutsch wie im Dashboard.
public enum SignalwerkFormat {
    public static let locale = Locale(identifier: "de_DE")
    public static let timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current

    /// 12055 → "12.055".
    public static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Kurz: "jetzt", "vor 5 Min.", "vor 2 Std.", "vor 3 Tagen".
    public static func ago(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 45 { return "jetzt" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "vor \(max(1, minutes)) Min." }
        let hours = Int((seconds / 3600).rounded(.down))
        if hours < 24 { return "vor \(hours) Std." }
        let days = Int((seconds / 86400).rounded(.down))
        return days == 1 ? "vor 1 Tag" : "vor \(days) Tagen"
    }

    /// Uhrzeit "14:05" in Berliner Zeit.
    public static func clock(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "Mo., 12.10. 14:05".
    public static func dayAndClock(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "EE, dd.MM. HH:mm"
        return formatter.string(from: date)
    }

    /// Laufzeit "3:08 h" oder "42 min".
    public static func duration(from start: Date?, to end: Date = Date()) -> String {
        guard let start else { return "" }
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d:%02d h", minutes / 60, minutes % 60)
    }

    /// Timeout-Dauer: 600 → "10 min", 3600 → "1 h", 86400 → "1 Tag".
    public static func timeout(_ seconds: Int) -> String {
        if seconds % 86400 == 0 {
            let days = seconds / 86400
            return days == 1 ? "1 Tag" : "\(days) Tage"
        }
        if seconds % 3600 == 0 { return "\(seconds / 3600) h" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return "\(seconds) s"
    }
}
