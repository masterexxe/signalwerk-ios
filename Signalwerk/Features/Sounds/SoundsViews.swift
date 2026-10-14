import SwiftUI
import SignalwerkKit

struct SoundsScreen: View {
    var body: some View {
        SoundsBoard()
            .navigationTitle("Sounds")
            .toolbar { EmergencyToolbar() }
    }
}

/// Tasten, Gesamtlautstärke und Hinweis; als eigener Bereich und im Arbeitsbereich.
struct SoundsBoard: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let store = session.sounds
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.sounds.count > 8 {
                    SoundSearchField()
                }
                SoundPadGrid(minimumWidth: 150)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text("Gesamtlautstärke \(store.master) %")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textMuted)
                .padding(.top, 4)
                .accessibilityElement(children: .combine)
                Text("Antippen spielt den Sound im OBS-Widget. Gedrückt halten zum Vorhören auf diesem Gerät. Die Gesamtlautstärke stellst du im Dashboard ein.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSubtle)
            }
            .padding(16)
        }
        .background(Palette.background)
        .refreshable { await store.load() }
        .task {
            if !store.loaded { await store.load() }
        }
        .onDisappear { store.stopPreview() }
    }
}

struct SoundSearchField: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        @Bindable var store = session.sounds
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.textSubtle)
            TextField("Sound suchen", text: $store.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textSubtle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche leeren")
            }
        }
        .fieldStyle()
    }
}

/// Tasten wie am Soundboard: Ziffer 1 bis 0, Farbstreifen je Sound, Vorhören per langem Druck.
struct SoundPadGrid: View {
    @Environment(AppSession.self) private var session
    var minimumWidth: CGFloat = 140
    var compact = false

    var body: some View {
        let store = session.sounds
        if store.loaded && store.sounds.isEmpty {
            EmptyNote(symbol: "speaker.slash", title: "Keine aktiven Sounds", text: "Sounds lädst du im Dashboard unter Soundboard → Sounds verwalten hoch.")
        } else if store.loaded && store.visible.isEmpty {
            EmptyNote(symbol: "magnifyingglass", title: "Kein Sound gefunden")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 10)], spacing: 10) {
                ForEach(Array(store.visible.enumerated()), id: \.element.id) { index, sound in
                    SoundPad(sound: sound, hotkey: SoundsStore.hotkey(for: index), compact: compact)
                }
            }
        }
    }
}

struct SoundPad: View {
    @Environment(AppSession.self) private var session
    let sound: Sound
    let hotkey: String?
    var compact = false

    var body: some View {
        let store = session.sounds
        let accent = Palette.soundAccent(sound.id)
        let firing = store.firing == sound.id
        let previewing = store.previewing == sound.id
        Button {
            Task { await store.play(sound) }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                if let hotkey {
                    Keycap(label: hotkey)
                }
                Text(sound.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if previewing {
                    Image(systemName: "headphones")
                        .font(.footnote)
                        .foregroundStyle(Palette.amber)
                        .symbolEffect(.pulse, options: .repeating)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: compact ? 50 : 60, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(firing ? accent.opacity(0.28) : Palette.surface2)
            )
            .overlay(alignment: .leading) {
                // Farbstreifen links wie im Dashboard.
                UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9, style: .continuous)
                    .fill(accent)
                    .frame(width: 4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(firing ? accent : Palette.line, lineWidth: firing ? 1.5 : 1)
            )
            .shadow(color: firing ? accent.opacity(0.5) : .clear, radius: 10)
            .animation(.easeOut(duration: 0.2), value: firing)
        }
        .buttonStyle(PadPressStyle())
        .disabled(!session.can(.playSounds))
        .modifier(PadHotkey(hotkey: hotkey))
        .contextMenu {
            Button {
                store.preview(sound)
            } label: {
                Label(previewing ? "Vorhören stoppen" : "Nur hier vorhören", systemImage: previewing ? "stop.fill" : "headphones")
            }
            Button {
                Task { await store.play(sound) }
            } label: {
                Label("Im OBS-Widget abspielen", systemImage: "play.fill")
            }
        }
        .accessibilityLabel(sound.name)
        .accessibilityHint("Spielt den Sound im OBS-Widget")
        .accessibilityIdentifier("sound-\(sound.name)")
    }
}

/// Ziffern 1 bis 0 auf der Tastatur am iPad.
struct PadHotkey: ViewModifier {
    let hotkey: String?

    func body(content: Content) -> some View {
        if let hotkey, let character = hotkey.first {
            content.keyboardShortcut(KeyEquivalent(character), modifiers: [])
        } else {
            content
        }
    }
}

struct PadPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
