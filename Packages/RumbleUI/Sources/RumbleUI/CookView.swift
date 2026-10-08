import RumbleServices
import RumbleState
import SwiftUI

struct CookView: View {
    let store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            // Card centred at phone width, pantry in a side column.
            HStack(alignment: .top, spacing: 24) {
                DeckView(store: store.cookDeck, emptyMessage: "Nothing you can cook right now. Try Shop mode.")
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                PantrySideView(items: store.pantryItems)
                    .frame(width: 320)
            }
            .padding()
        } else {
            DeckView(store: store.cookDeck, emptyMessage: "Nothing you can cook right now. Try Shop mode.")
        }
    }
}

struct PantrySideView: View {
    let items: [PantryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("At home").font(.headline)
            List(items) { item in
                LabeledContent(item.name, value: item.amount)
            }
            .listStyle(.plain)
        }
    }
}
