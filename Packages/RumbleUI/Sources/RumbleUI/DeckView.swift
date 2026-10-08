import RumbleServices
import RumbleState
import SwiftUI

/// A stack of the top three cards with a drag gesture on the front one.
/// The Yes / No buttons run the same animation for people who prefer tapping.
struct DeckView: View {
    let store: DeckStore
    let emptyMessage: String

    @State private var drag: CGSize = .zero
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 16) {
                ZStack {
                    if store.cards.isEmpty {
                        placeholder
                    } else {
                        ForEach(Array(store.visibleCards.enumerated().reversed()), id: \.element.id) { index, dish in
                            card(dish, at: index, width: proxy.size.width)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 48) {
                    Button { commit(.no, width: proxy.size.width) } label: {
                        Label("No", systemImage: "xmark").labelStyle(.iconOnly).font(.title).frame(width: 64, height: 64)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .accessibilityLabel("No")

                    Button { commit(.yes, width: proxy.size.width) } label: {
                        Label("Yes", systemImage: "heart.fill").labelStyle(.iconOnly).font(.title).frame(width: 64, height: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .accessibilityLabel("Yes")
                }
                .disabled(store.cards.isEmpty)
            }
            .padding()
        }
        .sensoryFeedback(.impact, trigger: store.swipeCount)
    }

    @ViewBuilder
    private func card(_ dish: Dish, at index: Int, width: CGFloat) -> some View {
        let isFront = index == 0
        DishCardView(dish: dish)
            .overlay { if isFront { verdictOverlay(width: width) } }
            .scaleEffect(1 - CGFloat(index) * 0.05)
            .offset(x: isFront ? drag.width : 0, y: CGFloat(index) * 14 + (isFront ? drag.height : 0))
            .rotationEffect(.degrees(isFront ? Double(drag.width / 20) : 0))
            .gesture(isFront ? dragGesture(width: width) : nil)
            // VoiceOver gets explicit Yes and No actions instead of the gesture.
            .accessibilityAction(named: "Yes") { if isFront { commit(.yes, width: width) } }
            .accessibilityAction(named: "No") { if isFront { commit(.no, width: width) } }
    }

    private func verdictOverlay(width: CGFloat) -> some View {
        let progress = min(1, abs(drag.width) / (width * 0.3))
        let isYes = drag.width > 0
        return Text(isYes ? "YES" : "NO")
            .font(.largeTitle.bold())
            .foregroundStyle(isYes ? .green : .red)
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isYes ? .green : .red, lineWidth: 4))
            .rotationEffect(.degrees(isYes ? -12 : 12))
            .opacity(progress)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isYes ? .topLeading : .topTrailing)
            .padding(24)
            .allowsHitTesting(false)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isAnimating else { return }
                drag = value.translation
            }
            .onEnded { value in
                // Past about 30% of the width, or a fast flick, commits; anything less springs back.
                let farEnough = abs(value.translation.width) > width * 0.3
                let flicked = abs(value.predictedEndTranslation.width) > width * 0.6
                if farEnough || flicked {
                    commit(value.translation.width > 0 ? .yes : .no, width: width)
                } else {
                    withAnimation(.spring) { drag = .zero }
                }
            }
    }

    private func commit(_ direction: SwipeDirection, width: CGFloat) {
        guard !isAnimating, !store.cards.isEmpty else { return }
        isAnimating = true
        withAnimation(.easeIn(duration: 0.22)) {
            drag = CGSize(width: direction == .yes ? width * 1.5 : -width * 1.5, height: drag.height)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            store.swipe(direction)
            drag = .zero  // not animated: the next card is already in place
            isAnimating = false
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if let message = store.errorMessage {
            ContentUnavailableView {
                Label("Offline", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { store.retry() }
            }
        } else if store.isLoading {
            ProgressView("Finding dishes…")
        } else {
            ContentUnavailableView("That's all for now", systemImage: "fork.knife", description: Text(emptyMessage))
        }
    }
}
