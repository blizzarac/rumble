import ActivityKit
import RumbleServices
import SwiftUI
import WidgetKit

/// Running kitchen timers on the Lock Screen and in the Dynamic Island, so nobody has to unlock with messy hands.
struct CookingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookingActivityAttributes.self) { context in
            LockScreenView(recipeTitle: context.attributes.recipeTitle, timers: context.state.timers)
                .padding()
        } dynamicIsland: { context in
            let timers = context.state.timers
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "fork.knife")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.recipeTitle).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimerRows(timers: timers)
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                if let next = timers.nextToFinish {
                    CountdownText(endDate: next.endDate).frame(width: 48)
                }
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}

private struct LockScreenView: View {
    let recipeTitle: String
    let timers: [TimerSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipeTitle).font(.headline)
            TimerRows(timers: timers)
        }
    }
}

private struct TimerRows: View {
    let timers: [TimerSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(timers) { timer in
                HStack {
                    Text(timer.label)
                    Spacer()
                    CountdownText(endDate: timer.endDate)
                }
            }
        }
    }
}

/// Counts down by itself, without the app having to push an update every second.
private struct CountdownText: View {
    let endDate: Date

    var body: some View {
        if endDate > .now {
            Text(timerInterval: .now...endDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Text("Done").bold().foregroundStyle(.orange)
        }
    }
}

private extension [TimerSnapshot] {
    /// The timer that ends next, or the first one when all have finished.
    var nextToFinish: TimerSnapshot? {
        filter { $0.endDate > .now }.min { $0.endDate < $1.endDate } ?? first
    }
}
