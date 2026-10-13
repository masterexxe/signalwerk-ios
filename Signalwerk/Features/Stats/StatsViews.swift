import SwiftUI
import SignalwerkKit

/// Statistik eines Kanals: laufender oder letzter Stream mit Verlauf.
struct StatsScreen: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let store = session.stats
        ScrollView {
            VStack(spacing: 16) {
                if let snapshot = store.snapshot {
                    Plate(title: snapshot.live ? "Live" : "Letzter Stream", tone: snapshot.live ? Palette.red : Palette.blue, lit: snapshot.live) {
                        if let started = SignalwerkDate.parse(snapshot.startedAt) {
                            Text(SignalwerkFormat.dayAndClock(started))
                                .font(.numeric(13))
                        }
                    } content: {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.title.isEmpty ? snapshot.login : snapshot.title)
                                    .font(.headline)
                                    .foregroundStyle(Palette.text)
                                Text(snapshot.category.isEmpty ? "#\(snapshot.login)" : "\(snapshot.category) · #\(snapshot.login)")
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.textMuted)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], alignment: .leading, spacing: 14) {
                                Metric(value: snapshot.live ? SignalwerkFormat.count(snapshot.viewers.last ?? 0) : "–", label: "Zuschauer jetzt", tone: Palette.blue)
                                Metric(value: SignalwerkFormat.count(snapshot.peak), label: "Spitze")
                                Metric(value: SignalwerkFormat.count(snapshot.average), label: "Durchschnitt")
                                Metric(value: SignalwerkFormat.count(snapshot.uniqueChatters), label: "Chatter gesamt", tone: Palette.violet)
                                Metric(value: duration(snapshot), label: "Laufzeit")
                            }
                            if snapshot.series.points.isEmpty {
                                Text(snapshot.tracked ? "Noch keine Messwerte für diesen Stream." : "Dieser Kanal wird nicht erfasst. Im Dashboard unter Statistiken einschalten.")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.textMuted)
                            } else {
                                ViewerChart(points: snapshot.series.points)
                                    .frame(height: 240)
                                HStack(spacing: 16) {
                                    Label("Zuschauer", systemImage: "circle.fill").foregroundStyle(Palette.blue)
                                    Label("Chatter", systemImage: "circle.fill").foregroundStyle(Palette.violet)
                                }
                                .font(.caption)
                                .labelStyle(LegendLabelStyle())
                            }
                        }
                    }
                } else if let message = store.message {
                    EmptyNote(symbol: "chart.xyaxis.line", title: "Keine Statistik", text: message)
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .padding(16)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .refreshable { await store.load() }
        .navigationTitle("Statistik")
        .toolbar {
            EmergencyToolbar()
            if store.channels.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(store.channels) { channel in
                            Button(channel.displayName) { store.select(channel.login) }
                        }
                    } label: {
                        Label(store.channels.first(where: { $0.login == store.login })?.displayName ?? "Kanal", systemImage: "chevron.down")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .task { await store.load() }
    }

    private func duration(_ snapshot: StreamSnapshot) -> String {
        guard let start = SignalwerkDate.parse(snapshot.startedAt) else { return "–" }
        if let end = SignalwerkDate.parse(snapshot.endedAt) {
            return SignalwerkFormat.duration(from: start, to: end)
        }
        if snapshot.live { return SignalwerkFormat.duration(from: start) }
        // Ohne Ende: bis zur letzten Messung.
        guard let last = snapshot.series.points.last?.date else { return "–" }
        return SignalwerkFormat.duration(from: start, to: last)
    }
}

struct LegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7))
            configuration.title.foregroundStyle(Palette.textMuted)
        }
    }
}
