import SwiftUI
import UIKit

/// Farben wie der Look „Pult“ im Dashboard: Graphit, Bernstein, Tally-Lampen, Klebeband.
enum Palette {
    static let background = Color(hex: 0x191C1F)
    static let sidebar = Color(hex: 0x16181B)
    static let surface = Color(hex: 0x1F2226)
    static let surface2 = Color(hex: 0x2A2E34)
    static let card = Color(hex: 0x24282D)
    static let accentSurface = Color(hex: 0x30353C)
    static let line = Color(hex: 0x353A41)
    static let lineStrong = Color(hex: 0x4A5058)
    static let input = Color(hex: 0x17191C)

    static let text = Color(hex: 0xECE7DC)
    static let textMuted = Color(hex: 0xA7A399)
    static let textSubtle = Color(hex: 0x77746D)

    static let amber = Color(hex: 0xFFB224)
    static let amberInk = Color(hex: 0x231503)
    static let green = Color(hex: 0x4CD07D)
    static let red = Color(hex: 0xFF4B3E)
    static let orange = Color(hex: 0xFF8C42)
    static let pink = Color(hex: 0xFF6FAE)
    static let violet = Color(hex: 0xA493FF)
    static let blue = Color(hex: 0x63C5FF)
    static let teal = Color(hex: 0x5FD4C3)

    static let tape = Color(hex: 0xEBE3CF)
    static let tapeInk = Color(hex: 0x1D1B17)

    /// Feste Farbe je Sound (wie soundAccent im Dashboard).
    static let soundAccents: [Color] = ([0x5B8CFF, 0x38BDF8, 0x3ECF8E, 0xF5A524, 0xA78BFA, 0xF472B6, 0xFB7185, 0x2DD4BF] as [UInt32]).map { Color(hex: $0) }

    static func soundAccent(_ id: String) -> Color {
        var hash: UInt32 = 0
        for unit in id.utf16 {
            hash = hash &* 31 &+ UInt32(unit)
        }
        return soundAccents[Int(hash % UInt32(soundAccents.count))]
    }

    /// Farbe eines Twitch-Namens; zu dunkle Farben werden aufgehellt, damit sie auf Graphit lesbar sind.
    static func chatName(_ hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let value = UInt32(clean, radix: 16) else { return violet }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luminance < 0.35 {
            let lift = 0.45
            return Color(red: r + (1 - r) * lift, green: g + (1 - g) * lift, blue: b + (1 - b) * lift)
        }
        return Color(red: r, green: g, blue: b)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Font {
    /// Schmale Schrift für Zahlen, Titel auf Klebeband und Tasten (wie Barlow Condensed im Pult).
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    static func numeric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed).monospacedDigit()
    }
}

/// Kurze Rückmeldung in der Hand.
@MainActor
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}
