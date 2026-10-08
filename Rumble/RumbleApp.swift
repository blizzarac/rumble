import RumbleServices
import RumbleState
import RumbleUI
import SwiftUI

@main
struct RumbleApp: App {
    @State private var store = AppStore(services: .live())

    var body: some Scene {
        WindowGroup {
            RumbleRootView(store: store)
        }
    }
}
