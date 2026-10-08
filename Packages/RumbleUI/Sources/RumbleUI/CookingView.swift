import RumbleServices
import RumbleState
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One step per page, Back and Next at the bottom, a timer on steps that need one.
struct CookingView: View {
    @Bindable var store: CookingStore
    let onFinish: () async -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            TimerStrip(store: store)

            if sizeClass == .regular {
                // Steps on the left, ingredients and timers on the right.
                HStack(alignment: .top, spacing: 24) {
                    steps
                    IngredientList(ingredients: store.recipe.ingredients).frame(width: 320)
                }
                .padding(.horizontal)
            } else {
                steps
            }
            controls
        }
        .onAppear { keepScreenAwake(true) }
        .onDisappear { keepScreenAwake(false) }
    }

    private var header: some View {
        HStack {
            Text(store.recipe.title).font(.headline)
            Spacer()
            Text("Step \(store.stepIndex + 1) of \(store.recipe.steps.count)")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Close") { dismiss() }.padding(.leading)
        }
        .padding()
    }

    private var steps: some View {
        TabView(selection: $store.stepIndex) {
            ForEach(store.recipe.steps) { step in
                StepPage(store: store, step: step, showIngredients: sizeClass != .regular)
                    .tag(step.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var controls: some View {
        HStack {
            Button("Back") { withAnimation { store.back() } }
                .buttonStyle(.bordered)
                .disabled(store.isFirstStep)
                .keyboardShortcut(.leftArrow, modifiers: [])
            Spacer()
            if store.isLastStep {
                Button("Finish") { Task { await onFinish() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.rightArrow, modifiers: [])
            } else {
                Button("Next") { withAnimation { store.next() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
        }
        .controlSize(.large)
        .padding()
    }

    /// The screen stays awake while cooking mode is open and is released when it closes.
    private func keepScreenAwake(_ on: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }
}

private struct StepPage: View {
    let store: CookingStore
    let step: RecipeStep
    let showIngredients: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(step.instruction).font(.title2)
                if let seconds = step.timerSeconds {
                    timerButton(seconds: seconds)
                }
                if showIngredients {
                    IngredientList(ingredients: store.recipe.ingredients)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func timerButton(seconds: Int) -> some View {
        if let timer = store.timer(for: step) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(format(timer.remaining(at: context.date)))
                    .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
            }
        } else {
            // Space starts or pauses a timer from a hardware keyboard.
            Button {
                store.startTimer(for: step)
            } label: {
                Label("Start \(format(TimeInterval(seconds))) timer", systemImage: "timer")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.space, modifiers: [])
        }
    }
}

/// Running timers as a small strip, visible on every step.
private struct TimerStrip: View {
    let store: CookingStore

    var body: some View {
        if !store.timers.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(store.timers) { timer in
                            let done = timer.isFinished(at: context.date)
                            HStack(spacing: 6) {
                                Image(systemName: done ? "bell.fill" : "timer")
                                Text("\(timer.label) · \(done ? "Done" : format(timer.remaining(at: context.date)))")
                                    .monospacedDigit()
                                Button("Remove timer", systemImage: "xmark.circle.fill") {
                                    store.cancelTimer(id: timer.id)
                                }
                                .labelStyle(.iconOnly)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(done ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.15), in: .capsule)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

private struct IngredientList: View {
    let ingredients: [Ingredient]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingredients").font(.headline)
            ForEach(ingredients) { ingredient in
                HStack {
                    Text(ingredient.amount).bold().foregroundStyle(.tint)
                    Text(ingredient.name)
                    Spacer()
                }
            }
        }
    }
}

private func format(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.up))
    return String(format: "%d:%02d", total / 60, total % 60)
}
