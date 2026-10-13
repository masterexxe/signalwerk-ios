import SwiftUI
import SignalwerkKit

/// Spenden und Sub-Bombs: offene zuerst, Wischen zum Annehmen (rechts) oder Blockieren (links).
struct QueueScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: QueueItem?

    var body: some View {
        let store = session.queue
        List {
            Section {
                QueueFilterPicker()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }
            Section {
                if store.loaded && store.items.isEmpty {
                    EmptyNote(
                        symbol: "checkmark.seal",
                        title: store.filter == .open ? "Nichts offen" : "Noch keine Spenden",
                        text: store.filter == .open ? "Neue Spenden und Sub-Bombs erscheinen hier sofort." : nil
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(store.items) { item in
                    // Am iPad (breite Ansicht) Tasten direkt in der Zeile, am iPhone wischen.
                    QueueRow(item: item, busy: store.busy.contains(item.key), inlineActions: sizeClass == .regular && session.can(.moderateDonations)) { action in
                        Task { await store.decide(item, action) }
                    }
                        .contentShape(Rectangle())
                        .onTapGesture { selected = item }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if item.isPending && session.can(.moderateDonations) {
                                Button {
                                    Task { await store.decide(item, .accept) }
                                } label: {
                                    Label("Annehmen", systemImage: "checkmark")
                                }
                                .tint(Palette.green)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if item.isPending && session.can(.moderateDonations) {
                                Button {
                                    Task { await store.decide(item, .block) }
                                } label: {
                                    Label("Blockieren", systemImage: "nosign")
                                }
                                .tint(Palette.red)
                            } else if item.isAccepted && session.can(.moderateDonations) {
                                Button {
                                    Task { await store.decide(item, .replay) }
                                } label: {
                                    Label("Wiederholen", systemImage: "arrow.counterclockwise")
                                }
                                .tint(Palette.amber)
                            }
                        }
                        .listRowBackground(Palette.card)
                        .accessibilityIdentifier("queue-row-\(item.id)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .refreshable { await store.load() }
        .navigationTitle("Spenden")
        .toolbar { EmergencyToolbar() }
        .sheet(item: $selected) { item in
            QueueDetailSheet(item: item)
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.surface)
        }
        .background(QueueKeyboardShortcuts())
        .task {
            if !store.loaded { await store.load() }
        }
    }
}

struct QueueFilterPicker: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let store = session.queue
        Picker("Anzeige", selection: Binding(get: { store.filter }, set: { store.setFilter($0) })) {
            Text(store.pending.total > 0 ? "Offen (\(store.pending.total))" : "Offen").tag(QueueFilter.open)
            Text("Alle").tag(QueueFilter.all)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("queue-filter")
    }
}

/// A nimmt, B blockiert die oberste offene Spende (Tastatur am iPad), wie im Dashboard.
struct QueueKeyboardShortcuts: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let store = session.queue
        ZStack {
            Button("Oberste offene Spende annehmen") {
                if let item = store.firstPending { Task { await store.decide(item, .accept) } }
            }
            .keyboardShortcut("a", modifiers: [])
            Button("Oberste offene Spende blockieren") {
                if let item = store.firstPending { Task { await store.decide(item, .block) } }
            }
            .keyboardShortcut("b", modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .disabled(!session.can(.moderateDonations))
    }
}

struct QueueRow: View {
    let item: QueueItem
    var busy = false
    /// Am iPad im Pult: Tasten direkt in der Zeile.
    var inlineActions = false
    var onDecide: ((QueueAction) -> Void)?

    private var amountColor: Color { item.isSubBomb ? Palette.pink : Palette.green }

    private var lampColor: Color {
        if item.isPending { return Palette.amber }
        return item.isAccepted ? Palette.green : Palette.red
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TallyLamp(color: lampColor, lit: item.isPending)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(SignalwerkFormat.ago(item.date, now: context.date))
                            .font(.caption)
                            .foregroundStyle(Palette.textSubtle)
                    }
                    Spacer(minLength: 8)
                    if item.isSubBomb {
                        Image(systemName: "gift.fill")
                            .font(.caption)
                            .foregroundStyle(amountColor)
                    }
                    Text(item.amountLabel)
                        .font(.numeric(19))
                        .foregroundStyle(amountColor)
                        .lineLimit(1)
                }
                if !item.message.isEmpty {
                    Text(item.message)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.isPending {
                    Text(item.isAccepted ? "Angenommen" : "Blockiert")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.isAccepted ? Palette.green : Palette.red)
                }
                if inlineActions && item.isPending {
                    HStack(spacing: 8) {
                        Button {
                            onDecide?(.accept)
                        } label: {
                            Label("Annehmen", systemImage: "checkmark")
                        }
                        .buttonStyle(PultKeyStyle(tone: Palette.green, filled: true, compact: true))
                        Button {
                            onDecide?(.block)
                        } label: {
                            Label("Blockieren", systemImage: "nosign")
                        }
                        .buttonStyle(PultKeyStyle(tone: Palette.red, compact: true))
                    }
                    .disabled(busy)
                    .padding(.top, 2)
                }
            }
            if busy {
                ProgressView()
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
        .opacity(item.isBlocked ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Eine Spende im Detail: ganze Nachricht, Stimme, Zeit; Entscheidung mit großen Tasten.
struct QueueDetailSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let item: QueueItem

    var body: some View {
        let store = session.queue
        let current = store.items.first(where: { $0.key == item.key }) ?? item
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(current.isSubBomb ? "Sub-Bomb" : "Spende")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textMuted)
                        Text(current.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Palette.text)
                    }
                    Spacer()
                    Text(current.amountLabel)
                        .font(.numeric(34, weight: .bold))
                        .foregroundStyle(current.isSubBomb ? Palette.pink : Palette.green)
                }
                if !current.message.isEmpty {
                    Text(current.message)
                        .font(.body)
                        .foregroundStyle(Palette.text)
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                HStack(spacing: 16) {
                    Label(SignalwerkFormat.dayAndClock(current.date), systemImage: "clock")
                    Label(current.voice == "default" || current.voice == "Default" ? "Standardstimme" : current.voice.capitalized, systemImage: "waveform")
                }
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)

                if session.can(.moderateDonations) {
                    if current.isPending {
                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    await store.decide(current, .accept)
                                    dismiss()
                                }
                            } label: {
                                Label("Annehmen", systemImage: "checkmark").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PultKeyStyle(tone: Palette.green, filled: true))
                            Button {
                                Task {
                                    await store.decide(current, .block)
                                    dismiss()
                                }
                            } label: {
                                Label("Blockieren", systemImage: "nosign").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PultKeyStyle(tone: Palette.red))
                        }
                        .disabled(store.busy.contains(current.key))
                    } else if current.isAccepted {
                        Button {
                            Task { await store.decide(current, .replay) }
                        } label: {
                            Label("Noch einmal vorlesen", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PultKeyStyle(tone: Palette.amber))
                    } else {
                        Label("Blockiert. Blockierte Spenden lassen sich nicht mehr ändern.", systemImage: "nosign")
                            .font(.footnote)
                            .foregroundStyle(Palette.red)
                    }
                }
            }
            .padding(22)
        }
    }
}
