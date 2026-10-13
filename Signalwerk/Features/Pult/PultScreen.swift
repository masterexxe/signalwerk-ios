import SwiftUI
import SignalwerkKit

/// iPad: alles auf einen Blick wie im Arbeitsbereich des Dashboards. Links die offenen Spenden,
/// in der Mitte Sounds und TTS, rechts der Chat. Schmaler (Hochformat, geteilter Bildschirm)
/// zwei Spalten; der Chat steht dann in der Seitenleiste.
struct PultScreen: View {
    @Environment(AppSession.self) private var session

    /// Höhe der Kopfzeile und der TTS-Platte; beide brauchen nicht mehr Platz.
    private static let stripHeight: CGFloat = 50
    private static let ttsHeight: CGFloat = 300
    private static let gap: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            // Jede Platte bekommt eine feste Größe. Sonst handeln die verschachtelten Stapel ihre
            // Größen bei jeder Änderung neu aus (Chatzeile, Bild, Uhr), und am iPad hing der
            // Hauptthread dann dauerhaft in der Layout-Berechnung.
            let gap = PultScreen.gap
            let width = max(0, geometry.size.width - gap * 2)
            let height = max(0, geometry.size.height - gap * 2)
            let wide = width >= 976
            let bodyHeight = max(320, height - PultScreen.stripHeight - gap)
            let queueWidth = (width * (wide ? 0.32 : 0.46)).rounded()
            let chatWidth = wide ? (width * 0.3).rounded() : 0
            let middleWidth = max(0, width - queueWidth - chatWidth - gap * (wide ? 2 : 1))
            let ttsHeight = min(PultScreen.ttsHeight, (bodyHeight * 0.6).rounded())
            VStack(alignment: .leading, spacing: gap) {
                PultStatusStrip()
                    .frame(width: width, height: PultScreen.stripHeight)
                HStack(alignment: .top, spacing: gap) {
                    PultQueuePlate()
                        .frame(width: queueWidth, height: bodyHeight)
                    VStack(spacing: gap) {
                        PultSoundsPlate()
                            .frame(width: middleWidth, height: max(0, bodyHeight - ttsHeight - gap))
                        TTSPanel(compact: true)
                            .frame(width: middleWidth, height: ttsHeight, alignment: .top)
                    }
                    .frame(width: middleWidth, height: bodyHeight, alignment: .top)
                    if wide {
                        ChatPanel(framed: true)
                            .frame(width: chatWidth, height: bodyHeight)
                    }
                }
                .frame(width: width, height: bodyHeight, alignment: .topLeading)
            }
            .padding(gap)
        }
        .background(Palette.background)
        .navigationTitle("Pult")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EmergencyToolbar() }
        .background(QueueKeyboardShortcuts())
    }
}

/// Kopfzeile: live, Zuschauer, offene Spenden, Summe heute, Alert-Dienst.
struct PultStatusStrip: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let overview = session.overview.overview
        let stream = overview?.stream
        let live = stream?.live == true
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                TallyLamp(color: live ? Palette.red : Palette.textSubtle, lit: live)
                Text(live ? "LIVE" : "offline")
                    .font(.display(15, weight: .bold))
                    .foregroundStyle(live ? Palette.red : Palette.textMuted)
            }
            strip(value: live ? SignalwerkFormat.count(stream?.viewers ?? 0) : "–", label: "Zuschauer", tone: Palette.blue)
            strip(value: "\(session.queue.pending.total)", label: "offen", tone: session.queue.pending.total > 0 ? Palette.amber : Palette.text)
            strip(value: overview?.stats.todaySumLabel ?? "–", label: "heute", tone: Palette.green)
            Spacer()
            if let system = overview?.system {
                HStack(spacing: 6) {
                    TallyLamp(color: system.alertsReachable ? Palette.green : Palette.red, size: 7)
                    Text(system.alertsReachable ? "Alert-Dienst" : "Alert-Dienst fehlt")
                        .font(.footnote)
                        .foregroundStyle(Palette.textMuted)
                    if let widgets = system.widgets {
                        TallyLamp(color: widgets.count > 0 ? Palette.green : Palette.orange, size: 7)
                            .padding(.leading, 8)
                        Text(widgets.count > 0 ? "OBS-Widget" : "OBS-Widget fehlt")
                            .font(.footnote)
                            .foregroundStyle(Palette.textMuted)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PlateBackground())
    }

    private func strip(value: String, label: String, tone: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.numeric(20, weight: .bold))
                .foregroundStyle(tone)
                .contentTransition(.numericText())
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
        }
    }
}

struct PultQueuePlate: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let store = session.queue
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TapeLabel(title: "Spenden", tone: Palette.green, lit: store.pending.total > 0)
                Spacer()
                Text("A annehmen · B blockieren")
                    .font(.caption)
                    .foregroundStyle(Palette.textSubtle)
            }
            QueueFilterPicker()
            ScrollView {
                LazyVStack(spacing: 8) {
                    if store.loaded && store.items.isEmpty {
                        EmptyNote(symbol: "checkmark.seal", title: store.filter == .open ? "Nichts offen" : "Noch keine Spenden")
                    }
                    ForEach(store.items) { item in
                        QueueRow(item: item, busy: store.busy.contains(item.key), inlineActions: session.can(.moderateDonations)) { action in
                            Task { await store.decide(item, action) }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Palette.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contextMenu {
                            if item.isAccepted {
                                Button {
                                    Task { await store.decide(item, .replay) }
                                } label: {
                                    Label("Noch einmal vorlesen", systemImage: "arrow.counterclockwise")
                                }
                            }
                        }
                    }
                }
            }
            .refreshable { await store.load() }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PlateBackground())
        .task { if !store.loaded { await store.load() } }
    }
}

struct PultSoundsPlate: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let store = session.sounds
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TapeLabel(title: "Sounds", tone: Palette.teal, lit: store.firing != nil)
                Spacer()
                Label("\(store.master) %", systemImage: "speaker.wave.2.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            }
            ScrollView {
                SoundPadGrid(minimumWidth: 130, compact: true)
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PlateBackground())
        .task { if !store.loaded { await store.load() } }
    }
}
