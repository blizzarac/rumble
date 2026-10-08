import RumbleServices
import RumbleState
import SwiftUI

/// The whole app: a Cook / Shop switch on top, the deck underneath. No home screen.
public struct RumbleRootView: View {
    @Bindable private var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $store.mode) {
                Text("Cook").tag(AppStore.Mode.cook)
                Text("Shop").tag(AppStore.Mode.shop)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            switch store.mode {
            case .cook: CookView(store: store)
            case .shop: ShopView(store: store)
            }
        }
        .task { await store.start() }
        .onChange(of: store.mode) { _, mode in
            if mode == .shop { store.shopDeck.start() }
        }
        .modifier(MatchPresentation(
            isPresented: Binding(
                get: { store.match != nil },
                set: { if !$0 { store.dismissMatch() } }
            ),
            // Sheet over the deck on iPad, full-screen takeover on iPhone.
            fullScreen: sizeClass != .regular
        ) {
            if let dish = store.match {
                MatchView(
                    dish: dish,
                    onCook: { Task { await store.startCooking(dish) } },
                    onKeepSwiping: { store.dismissMatch() }
                )
            }
        })
        .fullScreenCover(isPresented: Binding(
            get: { store.cooking != nil },
            set: { if !$0 { store.cancelCooking() } }
        )) {
            if let cooking = store.cooking {
                CookingView(store: cooking, onFinish: { await store.finishCooking() })
            }
        }
        .alert("Rumble", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct MatchPresentation<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let fullScreen: Bool
    @ViewBuilder let sheet: () -> Sheet

    func body(content: Content) -> some View {
        if fullScreen {
            content.fullScreenCover(isPresented: $isPresented, content: sheet)
        } else {
            content.sheet(isPresented: $isPresented, content: sheet)
        }
    }
}

#Preview("iPhone") {
    RumbleRootView(store: AppStore(services: .fake()))
}
