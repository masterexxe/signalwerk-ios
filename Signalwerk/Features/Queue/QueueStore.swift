import Foundation
import Observation
import SignalwerkKit

/// Spenden und Sub-Bombs: laden, annehmen, blockieren, wiederholen.
@MainActor
@Observable
final class QueueStore {
    private(set) var items: [QueueItem] = []
    private(set) var pending = PendingCounts(donations: 0, subBombs: 0)
    private(set) var filter: QueueFilter = .open
    private(set) var loaded = false
    private(set) var loading = false
    private(set) var busy: Set<String> = []

    private let context: SessionContext

    init(context: SessionContext) {
        self.context = context
    }

    var firstPending: QueueItem? { items.first(where: \.isPending) }

    func setFilter(_ next: QueueFilter) {
        guard next != filter else { return }
        filter = next
        Task { await load() }
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let response = try await context.backend.queue(filter: filter)
            // Während einer Entscheidung nicht zurückspringen: laufende bleiben, wie sie lokal sind.
            let local = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            let running = busy
            let openOnly = filter == .open
            items = response.items.compactMap { (item: QueueItem) -> QueueItem? in
                guard running.contains(item.key), let mine = local[item.key] else { return item }
                return openOnly && !mine.isPending ? nil : mine
            }
            pending = response.pending
            loaded = true
        } catch {
            context.report(error)
        }
    }

    func decide(_ item: QueueItem, _ action: QueueAction) async {
        guard !busy.contains(item.key) else { return }
        busy.insert(item.key)
        let before = items
        let beforePending = pending
        if action != .replay { applyLocally(item, action) }
        do {
            let outcome = try await context.backend.decide(item, action: action)
            busy.remove(item.key)
            Haptics.success()
            context.show(outcome, success: successText(item, action))
            await load()
        } catch {
            busy.remove(item.key)
            items = before
            pending = beforePending
            Haptics.error()
            context.report(error)
        }
    }

    private func applyLocally(_ item: QueueItem, _ action: QueueAction) {
        guard let index = items.firstIndex(where: { $0.key == item.key }) else { return }
        let wasPending = items[index].isPending
        if filter == .open {
            items.remove(at: index)
        } else {
            items[index].state = action == .accept ? "accepted" : "blocked"
        }
        if wasPending {
            pending = PendingCounts(
                donations: max(0, pending.donations - (item.isSubBomb ? 0 : 1)),
                subBombs: max(0, pending.subBombs - (item.isSubBomb ? 1 : 0))
            )
        }
    }

    private func successText(_ item: QueueItem, _ action: QueueAction) -> String {
        switch action {
        case .accept: return "Angenommen: \(item.name) · \(item.amountLabel)"
        case .block: return "Blockiert: \(item.name)"
        case .replay: return "Wird wiederholt: \(item.name)"
        }
    }
}
