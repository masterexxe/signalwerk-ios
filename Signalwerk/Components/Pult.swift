import SwiftUI

/// Tally-Lampe: kleiner Punkt in der Farbe des Bereichs, leuchtet, wenn etwas los ist.
struct TallyLamp: View {
    var color: Color
    var lit = true
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(lit ? color : color.opacity(0.28))
            .frame(width: size, height: size)
            .shadow(color: lit ? color.opacity(0.75) : .clear, radius: lit ? 4 : 0)
            .accessibilityHidden(true)
    }
}

/// Titel auf Klebeband wie im Pult-Look, mit Tally-Lampe davor.
struct TapeLabel: View {
    var title: String
    var tone: Color = Palette.amber
    var lit = true

    var body: some View {
        HStack(spacing: 8) {
            TallyLamp(color: tone, lit: lit)
            Text(title)
                .font(.display(15, weight: .semibold))
                .foregroundStyle(Palette.tapeInk)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Palette.tape, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Graphit-Platte: Rahmen für einen Bereich, mit Kopfzeile aus Klebeband und Zusatz rechts.
struct Plate<Trailing: View, Content: View>: View {
    var title: String
    var tone: Color
    var lit = true
    var padding: CGFloat = 14
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                TapeLabel(title: title, tone: tone, lit: lit)
                Spacer(minLength: 8)
                trailing()
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            }
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(PlateBackground())
    }
}

extension Plate where Trailing == EmptyView {
    init(title: String, tone: Color, lit: Bool = true, padding: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.tone = tone
        self.lit = lit
        self.padding = padding
        self.trailing = { EmptyView() }
        self.content = content
    }
}

struct PlateBackground: View {
    var corner: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient(colors: [Palette.card, Palette.surface], startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                // Lichtkante oben wie bei einer gebürsteten Platte.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            }
    }
}

/// Tastenkappe mit Ziffer (Sounds 1 bis 0) oder Buchstabe.
struct Keycap: View {
    var label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Palette.textMuted)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Palette.surface2)
                    .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Haupttaste: hinterleuchtet in Bernstein; gesperrt unbeleuchtet.
struct AmberKeyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Palette.amberInk : Color(hex: 0x9A8358))
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isEnabled
                        ? LinearGradient(colors: [Color(hex: 0xFFC14D), Palette.amber], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color(hex: 0x343940), Color(hex: 0x2B2F35)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: isEnabled ? Palette.amber.opacity(configuration.isPressed ? 0.15 : 0.35) : .clear, radius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Neutrale Taste aus Graphit, optional mit Farbe (Annehmen grün, Blockieren rot).
struct PultKeyStyle: ButtonStyle {
    var tone: Color = Palette.text
    var filled = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((compact ? Font.footnote : Font.subheadline).weight(.semibold))
            .foregroundStyle(filled ? Color.black.opacity(0.85) : tone)
            .padding(.vertical, compact ? 7 : 10)
            .padding(.horizontal, compact ? 10 : 14)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(filled ? tone.opacity(configuration.isPressed ? 0.8 : 1) : Palette.surface2.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(filled ? Color.black.opacity(0.2) : tone.opacity(0.35), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Hinweis, wenn eine Liste leer ist.
struct EmptyNote: View {
    var symbol: String
    var title: String
    var text: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Palette.textSubtle)
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.text)
            if let text {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
    }
}

/// Zahl mit kleiner Beschriftung darunter (Kennzahlen).
struct Metric: View {
    var value: String
    var label: String
    var tone: Color = Palette.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.numeric(26))
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

