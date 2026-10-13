import SwiftUI
import SignalwerkKit

struct SpeechScreen: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TTSPanel()
                LiveVoicePanel()
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background)
        .navigationTitle("Sprache")
        .toolbar { EmergencyToolbar() }
        .task { await session.speech.load() }
    }
}

/// Manuelle TTS: Text, Stimme, Tempo, Vorlesen. Zuletzt gesendete Texte zum Wiederholen.
struct TTSPanel: View {
    @Environment(AppSession.self) private var session
    @FocusState private var focused: Bool
    var compact = false

    var body: some View {
        @Bindable var store = session.speech
        Plate(title: "TTS", tone: Palette.blue, lit: store.sending) {
            Text("\(max(0, store.remaining))")
                .font(.numeric(13))
                .foregroundStyle(store.remaining < 0 ? Palette.red : Palette.textSubtle)
                .accessibilityLabel("\(store.remaining) Zeichen frei")
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .topLeading) {
                    if store.text.isEmpty {
                        Text("Was soll vorgelesen werden?")
                            .foregroundStyle(Palette.textSubtle)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $store.text)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(Palette.text)
                        .frame(minHeight: compact ? 90 : 110, maxHeight: compact ? 90 : 200)
                        .accessibilityIdentifier("tts-text")
                }
                .padding(8)
                .background(Palette.input, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(focused ? Palette.amber.opacity(0.7) : Palette.line, lineWidth: 1))

                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stimme")
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)
                        Picker("Stimme", selection: $store.voice) {
                            ForEach(store.voices) { voice in
                                Text(voice.name).tag(voice.value)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(Palette.text)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Tempo")
                                .font(.caption)
                                .foregroundStyle(Palette.textMuted)
                            Spacer()
                            Text(String(format: "%.2f×", store.speed).replacingOccurrences(of: ".", with: ","))
                                .font(.numeric(13))
                                .foregroundStyle(Palette.text)
                        }
                        Slider(value: $store.speed, in: 0.7...1.2, step: 0.05)
                            .tint(Palette.amber)
                            .accessibilityLabel("Tempo")
                    }
                }

                Button {
                    focused = false
                    Task { await store.send() }
                } label: {
                    HStack {
                        if store.sending {
                            ProgressView().tint(Palette.amberInk)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Vorlesen")
                    }
                }
                .buttonStyle(AmberKeyStyle())
                .disabled(!store.canSend || !session.can(.sendTTS))
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("tts-send")

                if !store.recent.isEmpty && !compact {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Zuletzt")
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)
                        ForEach(store.recent, id: \.self) { message in
                            Button {
                                store.reuse(message)
                                focused = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.caption)
                                        .foregroundStyle(Palette.textSubtle)
                                    Text(message)
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.textMuted)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
