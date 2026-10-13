import Charts
import SwiftUI
import SignalwerkKit

struct OverviewScreen: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let store = session.overview
        ScrollView {
            VStack(spacing: 16) {
                if let overview = store.overview {
                    StreamPlate(overview: overview)
                    TodayPlate(overview: overview)
                    SystemPlate(system: overview.system)
                } else {
                    ProgressView()
                        .padding(.top, 60)
                }
            }
            .padding(16)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .refreshable { await store.load() }
        .navigationTitle("Übersicht")
        .toolbar { EmergencyToolbar() }
        .task { if store.overview == nil { await store.load() } }
    }
}

/// Laufender Stream: Lampe, Titel, Zuschauer jetzt, Verlauf.
struct StreamPlate: View {
    let overview: Overview

    var body: some View {
        let stream = overview.stream
        let live = stream?.live == true
        Plate(title: live ? "Live" : "Stream", tone: live ? Palette.red : Palette.textSubtle, lit: live) {
            if let started = SignalwerkDate.parse(stream?.startedAt), live {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text("seit \(SignalwerkFormat.duration(from: started, to: context.date))")
                        .font(.numeric(13))
                }
            }
        } content: {
            if let stream {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stream.title.isEmpty ? stream.login : stream.title)
                            .font(.headline)
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                        Text(stream.category.isEmpty ? "#\(stream.login)" : "\(stream.category) · #\(stream.login)")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textMuted)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Metric(value: live ? SignalwerkFormat.count(stream.viewers) : "–", label: "Zuschauer", tone: Palette.blue)
                        Metric(value: SignalwerkFormat.count(stream.peak), label: "Spitze")
                        Metric(value: live ? SignalwerkFormat.count(stream.chatters) : "–", label: "Chatter", tone: Palette.violet)
                    }
                    if !stream.series.points.isEmpty {
                        ViewerChart(points: stream.series.points)
                            .frame(height: 150)
                    }
                }
            } else {
                Text("Kein Kanal erfasst. Kanäle legst du im Dashboard unter Statistiken an.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textMuted)
            }
        }
    }
}

/// Zuschauer und Chatter über die Zeit.
struct ViewerChart: View {
    let points: [StreamSeries.Point]
    var showChatters = true

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Zeit", point.date), y: .value("Zuschauer", point.viewers))
                    .foregroundStyle(LinearGradient(colors: [Palette.blue.opacity(0.35), Palette.blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Zeit", point.date), y: .value("Zuschauer", point.viewers), series: .value("Reihe", "Zuschauer"))
                    .foregroundStyle(Palette.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                if showChatters {
                    LineMark(x: .value("Zeit", point.date), y: .value("Chatter", point.chatters), series: .value("Reihe", "Chatter"))
                        .foregroundStyle(Palette.violet)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(Palette.line)
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(Palette.textSubtle)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.line)
                AxisValueLabel()
                    .foregroundStyle(Palette.textSubtle)
            }
        }
        .accessibilityLabel("Zuschauerverlauf")
    }
}

/// Zahlen von heute.
struct TodayPlate: View {
    let overview: Overview

    var body: some View {
        let stats = overview.stats
        Plate(title: "Heute", tone: Palette.green) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Metric(value: stats.todaySumLabel, label: "\(stats.todayCount) Spenden", tone: Palette.green)
                    Metric(value: "\(overview.pending.total)", label: "warten auf dich", tone: overview.pending.total > 0 ? Palette.amber : Palette.text)
                    Metric(value: "\(stats.todaySubBombs)", label: "Sub-Bombs · \(stats.todayGiftedSubs) Abos", tone: Palette.pink)
                }
                if let last = stats.lastDonation {
                    HStack {
                        Text("Letzte Spende")
                            .font(.footnote)
                            .foregroundStyle(Palette.textMuted)
                        Spacer()
                        Text("\(last.name) · \(last.amount) · \(SignalwerkFormat.ago(SignalwerkDate.parse(last.at)))")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                    }
                }
                if let top = stats.todayTop {
                    HStack {
                        Text("Größte heute")
                            .font(.footnote)
                            .foregroundStyle(Palette.textMuted)
                        Spacer()
                        Text("\(top.name) · \(top.amount)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

/// Technik: Alert-Dienst, Streamlabs, Sprache, OBS-Widget, Live-Voice.
struct SystemPlate: View {
    let system: SystemSummary

    var body: some View {
        let issues = rows.filter { $0.state == .problem }.count
        Plate(title: "Technik", tone: issues > 0 ? Palette.orange : Palette.green) {
            Text(issues == 0 ? "alles bereit" : "\(issues) Hinweis\(issues == 1 ? "" : "e")")
        } content: {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack {
                        TallyLamp(color: row.state.color, lit: row.state != .off, size: 7)
                        Text(row.name)
                            .font(.subheadline)
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(row.detail)
                            .font(.subheadline)
                            .foregroundStyle(row.state == .problem ? Palette.orange : Palette.textMuted)
                    }
                    .padding(.vertical, 9)
                    if row.id != rows.last?.id {
                        Divider().overlay(Palette.line)
                    }
                }
            }
        }
    }

    struct Row: Identifiable {
        enum State { case ok, problem, off
            var color: Color {
                switch self {
                case .ok: return Palette.green
                case .problem: return Palette.orange
                case .off: return Palette.textSubtle
                }
            }
        }
        let id: String
        let name: String
        let state: State
        let detail: String
    }

    var rows: [Row] {
        var result: [Row] = [
            Row(id: "alerts", name: "Alert-Dienst", state: system.alertsReachable ? .ok : .problem, detail: system.alertsReachable ? (system.alertsVersion.isEmpty ? "online" : "online · \(system.alertsVersion)") : "nicht erreichbar"),
        ]
        switch system.streamlabs {
        case "connected": result.append(Row(id: "streamlabs", name: "Streamlabs", state: .ok, detail: "verbunden"))
        case "connecting": result.append(Row(id: "streamlabs", name: "Streamlabs", state: .problem, detail: "verbindet …"))
        case "disabled": result.append(Row(id: "streamlabs", name: "Streamlabs", state: .off, detail: "aus"))
        default: result.append(Row(id: "streamlabs", name: "Streamlabs", state: .problem, detail: "unbekannt"))
        }
        result.append(Row(id: "tts", name: "Sprache", state: system.tts == "elevenlabs" ? .ok : .problem, detail: system.tts == "elevenlabs" ? "ElevenLabs" : "Testmodus"))
        if let widgets = system.widgets {
            let detail = widgets.count == 0 ? "nicht verbunden" : (widgets.outdated > 0 ? "\(widgets.count) verbunden, \(widgets.outdated) veraltet" : "\(widgets.count) verbunden")
            result.append(Row(id: "widget", name: "OBS-Widget", state: widgets.count > 0 && widgets.outdated == 0 ? .ok : .problem, detail: detail))
        }
        if let voice = system.liveVoice {
            result.append(Row(id: "voice", name: "Live-Voice", state: voice.active ? .ok : .off, detail: voice.active ? "läuft" : "aus"))
        }
        return result
    }
}
