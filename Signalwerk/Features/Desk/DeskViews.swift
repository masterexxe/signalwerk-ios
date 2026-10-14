import SwiftUI
import SignalwerkKit

/// Arbeitsbereich: oben der Twitch-Player, darunter Spenden, Sounds, TTS und Live-Voice als
/// Reiter. Am iPhone im Querformat nur der Player, bildschirmfüllend.
struct DeskScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var twitchLogin = false

    var body: some View {
        @Bindable var desk = session.desk
        let fullscreen = verticalSizeClass == .compact
        GeometryReader { geometry in
            let width = geometry.size.width
            let playerHeight: CGFloat = fullscreen
                ? geometry.size.height
                : (desk.playerOpen ? min((width * 9 / 16).rounded(), (geometry.size.height * 0.5).rounded()) : DeskPlayer.barHeight)
            VStack(spacing: 0) {
                DeskPlayer(fullscreen: fullscreen)
                    .frame(width: width, height: playerHeight)
                if !fullscreen {
                    Picker("Bereich", selection: $desk.tab) {
                        ForEach(DeskTab.allCases) { tab in
                            Text(label(for: tab)).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("desk-tabs")
                    DeskTabContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Palette.background)
        .ignoresSafeArea(.container, edges: fullscreen ? .all : [])
        .navigationTitle("Arbeitsbereich")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !fullscreen {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        desk.togglePlayer()
                    } label: {
                        Image(systemName: desk.playerOpen ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    }
                    .accessibilityLabel(desk.playerOpen ? "Player einklappen, Ton läuft weiter" : "Player zeigen")
                    .accessibilityIdentifier("desk-player-toggle")
                }
                ToolbarItem(placement: .principal) {
                    DeskChannelMenu { twitchLogin = true }
                }
                EmergencyToolbar()
            }
        }
        .toolbar(fullscreen ? .hidden : .automatic, for: .navigationBar, .tabBar)
        .background(QueueKeyboardShortcuts())
        .task { await desk.load() }
        .task { await desk.refreshTwitch() }
        .onChange(of: scenePhase) { _, phase in
            // Twitch meldet nach einiger Zeit ab; beim Zurückkommen den Stand neu lesen.
            if phase == .active { Task { await desk.refreshTwitch() } }
        }
        .sheet(isPresented: $twitchLogin) {
            TwitchLoginSheet()
                .environment(session)
        }
    }

    private func label(for tab: DeskTab) -> String {
        let pending = session.queue.pending.total
        return tab == .queue && pending > 0 ? "\(tab.title) (\(pending))" : tab.title
    }
}

/// Menü des Players oben in der Mitte: Kanal (bei mehreren), Twitch-Anmeldung, neu laden.
struct DeskChannelMenu: View {
    @Environment(AppSession.self) private var session
    var onTwitchLogin: () -> Void

    var body: some View {
        let desk = session.desk
        Menu {
            if desk.channels.count > 1 {
                Section("Kanal im Player") {
                    ForEach(desk.channels) { channel in
                        Button {
                            desk.select(channel.login)
                        } label: {
                            if channel.login == desk.channel {
                                Label(channel.displayName, systemImage: "checkmark")
                            } else {
                                Text(channel.displayName)
                            }
                        }
                    }
                }
            }
            Section {
                if desk.twitchAccount != nil {
                    Button(role: .destructive) {
                        Task { await desk.signOutTwitch() }
                    } label: {
                        Label("Bei Twitch abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
                        onTwitchLogin()
                    } label: {
                        Label("Bei Twitch anmelden", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
            } header: {
                Text(desk.twitchAccount.map { "Twitch: angemeldet als \($0.label)" } ?? "Twitch: nicht angemeldet")
            }
            if !session.isDemo && desk.channel != nil {
                Button {
                    desk.reloadPlayer()
                } label: {
                    Label("Player neu laden", systemImage: "arrow.clockwise")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(desk.channel == nil ? "Arbeitsbereich" : desk.channelName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .accessibilityLabel("Player: Kanal und Twitch-Anmeldung")
        .accessibilityIdentifier("desk-player-menu")
    }
}

/// Der Player selbst, eingeklappt als schmale Leiste (der Ton läuft weiter). Während Live-Voice
/// ist sein Ton aus: Sonst nähme das Mikrofon den Stream-Ton wieder auf.
struct DeskPlayer: View {
    static let barHeight: CGFloat = 44

    @Environment(AppSession.self) private var session
    var fullscreen = false
    @State private var state: TwitchPlayerState = .loading

    var body: some View {
        let desk = session.desk
        let open = desk.playerOpen || fullscreen
        let voiceActive = session.liveVoice.isActive
        ZStack {
            Color.black
            if session.isDemo {
                note("In der Demo läuft kein Stream.", symbol: "play.slash")
                    .opacity(open ? 1 : 0)
            } else if let channel = desk.channel {
                TwitchPlayerView(channel: channel, reload: desk.playerReload, muted: voiceActive) { state = $0 }
                    .opacity(open ? 1 : 0.02)
                    .allowsHitTesting(open)
                    .accessibilityLabel("Stream von \(desk.channelName)")
                if open, case .failed(let message) = state {
                    VStack(spacing: 10) {
                        note(message, symbol: "exclamationmark.triangle")
                        Button("Noch einmal laden") { desk.reloadPlayer() }
                            .buttonStyle(PultKeyStyle(tone: Palette.amber, compact: true))
                    }
                }
                if open && voiceActive {
                    Label("Ton aus, solange Live-Voice läuft", systemImage: "mic.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Palette.red.opacity(0.85), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 10)
                }
            } else {
                note(desk.noChannel ? "Im Dashboard ist noch kein Twitch-Kanal eingerichtet." : "Kanal wird geladen …", symbol: "tv")
                    .opacity(open ? 1 : 0)
            }
            if !open {
                collapsedBar(voiceActive: voiceActive)
            }
        }
        .clipped()
        .onAppear { if !session.isDemo { PlayerAudio.prepare() } }
        .onChange(of: voiceActive) { _, active in
            // Live-Voice stellt die Audio-Sitzung auf Aufnahme; danach wieder auf Wiedergabe.
            if !active && !session.isDemo { PlayerAudio.prepare() }
        }
    }

    private func collapsedBar(voiceActive: Bool) -> some View {
        let desk = session.desk
        return HStack(spacing: 10) {
            TallyLamp(color: state == .playing && !voiceActive ? Palette.red : Palette.textSubtle, lit: state == .playing && !voiceActive, size: 7)
            Text(desk.channel == nil ? "Player" : desk.channelName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
            Text(voiceActive ? "Ton aus (Live-Voice)" : (state == .playing ? "Ton läuft" : ""))
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                desk.togglePlayer()
            } label: {
                Label("Player zeigen", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textMuted)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
    }

    private func note(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Palette.textSubtle)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(16)
    }
}

/// Inhalt des gewählten Reiters unter dem Player.
struct DeskTabContent: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        switch session.desk.tab {
        case .queue:
            QueueList()
        case .sounds:
            SoundsBoard()
        case .tts:
            ScrollView {
                TTSPanel()
                    .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background)
            .task { await session.speech.load() }
        case .voice:
            ScrollView {
                LiveVoicePanel()
                    .padding(16)
            }
            .background(Palette.background)
        }
    }
}
