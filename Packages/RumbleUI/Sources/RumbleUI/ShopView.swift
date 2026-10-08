import RumbleServices
import RumbleState
import SwiftUI

struct ShopView: View {
    let store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            // Plan on the left, list on the right.
            HStack(alignment: .top, spacing: 24) {
                planColumn
                if store.plan.shoppingList != nil {
                    ShoppingListView(plan: store.plan, onDone: finishShopping).frame(width: 380)
                } else {
                    ContentUnavailableView(
                        "Your list appears here",
                        systemImage: "cart",
                        description: Text("Pick \(store.plan.targetCount) dinners and the list builds itself.")
                    )
                    .frame(width: 380)
                }
            }
            .padding()
        } else if store.plan.shoppingList != nil {
            ShoppingListView(plan: store.plan, onDone: finishShopping)
        } else {
            planColumn
        }
    }

    private var planColumn: some View {
        VStack(spacing: 8) {
            Text("Dinner \(min(store.plan.selected.count + 1, store.plan.targetCount)) of \(store.plan.targetCount)")
                .font(.headline)
                .padding(.top)
            if !store.plan.selected.isEmpty {
                Text(store.plan.selected.map(\.title).joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if store.plan.isBuilding { ProgressView("Building your list…") }
            DeckView(store: store.shopDeck, emptyMessage: "No more dishes right now.")
        }
        .frame(maxWidth: 480)
    }

    private func finishShopping() { Task { await store.finishShopping() } }
}

struct ShoppingListView: View {
    let plan: PlanStore
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Shopping list") {
                    ForEach(plan.shoppingList?.items ?? []) { item in
                        Button { plan.toggle(itemID: item.id) } label: {
                            HStack {
                                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isChecked ? Color.green : Color.secondary)
                                Text(item.name).strikethrough(item.isChecked)
                                Spacer()
                                Text(item.amount).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
                    }
                }
            }
            Button(action: onDone) {
                Text("Done shopping (\(plan.checkedCount) bought)").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
    }
}
