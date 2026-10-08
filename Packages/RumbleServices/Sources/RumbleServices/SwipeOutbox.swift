import Foundation

/// Queues swipes and sends them in order; keeps them queued while the backend is unreachable.
///
/// TODO: persist the queue in SwiftData so it survives a relaunch (in memory for now).
public actor SwipeOutbox {
    private let deck: any DeckService
    private var pending: [Swipe] = []
    private var isFlushing = false

    public init(deck: any DeckService) {
        self.deck = deck
    }

    public var pendingCount: Int { pending.count }

    public func enqueue(_ swipe: Swipe) async {
        pending.append(swipe)
        await flush()
    }

    /// Sends queued swipes in order; stops at the first failure and keeps the rest.
    public func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        while let next = pending.first {
            do {
                try await deck.recordSwipe(next)
                pending.removeFirst()
            } catch {
                return
            }
        }
    }
}
