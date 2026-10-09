import Foundation

/// Queues swipes and sends them in order; keeps them queued while the backend is unreachable.
/// With a storage the queue survives a relaunch.
public actor SwipeOutbox {
    private let deck: any DeckService
    private let storage: (any SwipeQueueStorage)?
    private var pending: [Swipe] = []
    private var isFlushing = false

    public init(deck: any DeckService, storage: (any SwipeQueueStorage)? = nil) {
        self.deck = deck
        self.storage = storage
    }

    public var pendingCount: Int { pending.count }

    /// Loads swipes left over from a previous launch and sends them. Call once at startup.
    public func restore() async {
        if pending.isEmpty, let stored = try? await storage?.pendingSwipes() {
            pending = stored
        }
        await flush()
    }

    public func enqueue(_ swipe: Swipe) async {
        try? await storage?.appendSwipe(swipe)
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
                try? await storage?.removeOldestSwipe()
            } catch {
                return
            }
        }
    }
}
