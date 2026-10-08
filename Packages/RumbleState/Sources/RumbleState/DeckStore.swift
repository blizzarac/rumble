import Foundation
import Observation
import RumbleServices

/// The swipe deck: keeps a buffer of cards ahead of the user and queues every swipe for sending.
@MainActor @Observable
public final class DeckStore {
    public let mode: DeckMode
    public let bufferSize: Int

    public private(set) var cards: [Dish] = []
    public private(set) var isExhausted = false
    public private(set) var errorMessage: String?
    /// Increments on every swipe; views use it to trigger haptics.
    public private(set) var swipeCount = 0

    /// Called when the user swipes a dish to "yes".
    @ObservationIgnored public var onAccept: (Dish) -> Void = { _ in }

    @ObservationIgnored private let deck: any DeckService
    @ObservationIgnored private let outbox: SwipeOutbox
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(mode: DeckMode, deck: any DeckService, outbox: SwipeOutbox, bufferSize: Int = 20) {
        self.mode = mode
        self.deck = deck
        self.outbox = outbox
        self.bufferSize = bufferSize
    }

    /// The top three cards, front card first.
    public var visibleCards: [Dish] { Array(cards.prefix(3)) }
    public var isLoading: Bool { cards.isEmpty && !isExhausted && errorMessage == nil }

    public func start() {
        guard loadTask == nil else { return }
        loadTask = Task { await load() }
    }

    public func retry() {
        loadTask?.cancel()
        loadTask = nil
        errorMessage = nil
        isExhausted = false
        start()
    }

    public func swipe(_ direction: SwipeDirection) {
        guard !cards.isEmpty else { return }
        let dish = cards.removeFirst()
        swipeCount += 1
        let swipe = Swipe(dishID: dish.id, direction: direction, date: Date())
        let outbox = outbox
        Task { await outbox.enqueue(swipe) }
        if direction == .yes { onAccept(dish) }
    }

    private func load() async {
        do {
            for try await dish in deck.streamDeck(mode: mode) {
                while cards.count >= bufferSize {
                    try await Task.sleep(for: .milliseconds(150))
                }
                cards.append(dish)
            }
            isExhausted = true
        } catch is CancellationError {
            // Restarted or torn down.
        } catch {
            errorMessage = error.rumbleUserMessage
        }
    }
}
