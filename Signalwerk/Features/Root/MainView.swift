import SwiftUI
import SignalwerkKit

/// Bereiche der App. Auf dem iPhone Reiter, auf dem iPad eine Seitenleiste mit dem Pult zuerst.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case pult
    case overview
    case queue
    case sounds
    case speech
    case chat
    case stats
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pult: return "Pult"
        case .overview: return "Übersicht"
        case .queue: return "Spenden"
        case .sounds: return "Sounds"
        case .speech: return "Sprache"
        case .chat: return "Chat"
        case .stats: return "Statistik"
        case .settings: return "Einstellungen"
        }
    }

    var symbol: String {
        switch self {
        case .pult: return "slider.horizontal.below.square.and.square.filled"
        case .overview: return "gauge.with.dots.needle.33percent"
        case .queue: return "eurosign.circle"
        case .sounds: return "square.grid.3x3.fill"
        case .speech: return "text.bubble"
        case .chat: return "bubble.left.and.bubble.right"
        case .stats: return "chart.xyaxis.line"
        case .settings: return "gearshape"
        }
    }

    var tone: Color {
        switch self {
        case .pult: return Palette.amber
        case .overview: return Palette.blue
        case .queue: return Palette.green
        case .sounds: return Palette.teal
        case .speech: return Palette.blue
        case .chat: return Palette.violet
        case .stats: return Palette.blue
        case .settings: return Palette.textMuted
        }
    }
}

struct MainView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            SplitLayout()
        } else {
            TabLayout()
        }
    }
}

/// iPhone (und schmale iPad-Fenster): Reiter unten.
struct TabLayout: View {
    @Environment(AppSession.self) private var session
    @State private var tab: AppSection = .queue

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { QueueScreen() }
                .tabItem { Label("Spenden", systemImage: AppSection.queue.symbol) }
                .badge(session.queue.pending.total)
                .tag(AppSection.queue)
            NavigationStack { SoundsScreen() }
                .tabItem { Label("Sounds", systemImage: AppSection.sounds.symbol) }
                .tag(AppSection.sounds)
            NavigationStack { SpeechScreen() }
                .tabItem { Label("Sprache", systemImage: AppSection.speech.symbol) }
                .tag(AppSection.speech)
            NavigationStack { ChatScreen() }
                .tabItem { Label("Chat", systemImage: AppSection.chat.symbol) }
                .tag(AppSection.chat)
            NavigationStack { MoreScreen() }
                .tabItem { Label("Mehr", systemImage: "ellipsis.circle") }
                .tag(AppSection.overview)
        }
        .onChange(of: PushCenter.shared.openedItem) { _, opened in
            // Mitteilung angetippt: zu den Spenden.
            if opened != nil {
                tab = .queue
                PushCenter.shared.openedItem = nil
            }
        }
    }
}

/// iPad: Seitenleiste, rechts der gewählte Bereich.
struct SplitLayout: View {
    @Environment(AppSession.self) private var session
    @State private var selection: AppSection? = .pult
    @State private var visibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            List(selection: $selection) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        NavigationLink(value: section) {
                            Label {
                                HStack {
                                    Text(section.title)
                                    Spacer()
                                    if section == .queue, session.queue.pending.total > 0 {
                                        Text("\(session.queue.pending.total)")
                                            .font(.numeric(13))
                                            .foregroundStyle(Palette.amberInk)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 1)
                                            .background(Palette.amber, in: Capsule())
                                    }
                                }
                            } icon: {
                                Image(systemName: section.symbol)
                                    .foregroundStyle(section.tone)
                            }
                        }
                        .accessibilityIdentifier("nav-\(section.rawValue)")
                    }
                } header: {
                    SidebarHeader()
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Palette.sidebar)
            .navigationTitle("Signalwerk")
        } detail: {
            NavigationStack {
                detail(for: selection ?? .pult)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: PushCenter.shared.openedItem) { _, opened in
            if opened != nil {
                selection = .queue
                PushCenter.shared.openedItem = nil
            }
        }
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .pult: PultScreen()
        case .overview: OverviewScreen()
        case .queue: QueueScreen()
        case .sounds: SoundsScreen()
        case .speech: SpeechScreen()
        case .chat: ChatScreen()
        case .stats: StatsScreen()
        case .settings: SettingsScreen()
        }
    }
}

/// Kopf der Seitenleiste: wer angemeldet ist, ob live.
struct SidebarHeader: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        HStack(spacing: 10) {
            BrandMark(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.user.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
                HStack(spacing: 5) {
                    TallyLamp(color: session.live ? Palette.green : Palette.textSubtle, lit: session.live, size: 6)
                    Text(session.isDemo ? "Demo" : (session.live ? "verbunden" : "verbindet …"))
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                }
            }
        }
        .textCase(nil)
        .padding(.vertical, 8)
    }
}

/// iPhone: Übersicht, Statistik und Einstellungen unter „Mehr“.
struct MoreScreen: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        List {
            Section {
                NavigationLink { OverviewScreen() } label: {
                    Label("Übersicht", systemImage: AppSection.overview.symbol)
                }
                NavigationLink { StatsScreen() } label: {
                    Label("Statistik", systemImage: AppSection.stats.symbol)
                }
                NavigationLink { SettingsScreen() } label: {
                    Label("Einstellungen", systemImage: AppSection.settings.symbol)
                }
            }
            .listRowBackground(Palette.card)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Mehr")
        .toolbar { EmergencyToolbar() }
    }
}

/// Notbremse oben rechts in jedem Bereich.
struct EmergencyToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            EmergencyStopButton()
        }
    }
}

struct EmergencyStopButton: View {
    @Environment(AppSession.self) private var session
    var expanded = false

    var body: some View {
        Button {
            Task { await session.emergencyStop() }
        } label: {
            HStack(spacing: 6) {
                if session.stopping {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "octagon.fill")
                }
                Text("Notbremse")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(LinearGradient(colors: [Color(hex: 0xFF6A5E), Palette.red], startPoint: .top, endPoint: .bottom))
            )
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            .shadow(color: Palette.red.opacity(0.4), radius: 6)
        }
        .buttonStyle(.plain)
        .disabled(session.stopping || !session.can(.stopAlerts))
        .accessibilityLabel("Notbremse: alle Alerts stoppen")
        .accessibilityIdentifier("notbremse")
    }
}
