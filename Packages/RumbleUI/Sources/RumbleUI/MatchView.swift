import RumbleServices
import SwiftUI

struct MatchView: View {
    let dish: Dish
    let onCook: () -> Void
    let onKeepSwiping: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("It's a match!").font(.largeTitle.bold())
            DishCardView(dish: dish).frame(maxWidth: 420, maxHeight: 520)
            VStack(spacing: 12) {
                Button(action: onCook) {
                    Text("Let's cook").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Keep swiping", action: onKeepSwiping)
            }
            .frame(maxWidth: 420)
        }
        .padding()
    }
}
