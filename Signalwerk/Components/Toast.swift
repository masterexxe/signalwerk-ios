import SwiftUI
import Observation

/// Kurze Rückmeldungen unten am Rand: erledigt, Hinweis vom Dashboard, Fehler.
@MainActor
@Observable
final class ToastCenter {
    enum Style {
        case success, warning, error, info

        var color: Color {
            switch self {
            case .success: return Palette.green
            case .warning: return Palette.orange
            case .error: return Palette.red
            case .info: return Palette.blue
            }
        }

        var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let style: Style
        let text: String

        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    private(set) var current: Toast?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, style: Style = .success, seconds: Double = 3.2) {
        let toast = Toast(style: style, text: text)
        withAnimation(.spring(duration: 0.3)) { current = toast }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss(toast)
        }
    }

    /// Fehler zeigen; Hinweise vom Dashboard (Warnungen) als Warnung, sonst Erfolg mit Text.
    func show(error: Error) {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        show(text, style: .error, seconds: 4.5)
    }

    func dismiss(_ toast: Toast? = nil) {
        guard toast == nil || current?.id == toast?.id else { return }
        withAnimation(.easeOut(duration: 0.25)) { current = nil }
    }
}

struct ToastOverlay: View {
    var center: ToastCenter

    var body: some View {
        VStack {
            Spacer()
            if let toast = center.current {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: toast.style.symbol)
                        .foregroundStyle(toast.style.color)
                    Text(toast.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 520, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.surface2)
                        .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(toast.style.color.opacity(0.45), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { center.dismiss() }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("toast")
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(center.current != nil)
    }
}
