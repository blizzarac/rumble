import Foundation
import RumbleServices
import RumbleState

extension AppServices {
    /// Real on-device storage, notifications and Live Activities. The network services are still
    /// the fakes until the gRPC adapters over RumbleProto exist (they will be built on `CallPipeline`).
    @MainActor
    static func live() -> AppServices {
        // UI tests run on fakes with nothing stored on the device.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return AppServices.fake(streamDelay: .milliseconds(10))
        }
        var services = AppServices.fake()
        do {
            let container = try RumbleStorage.makeContainer()
            let pantry = SwiftDataPantryService(modelContainer: container)
            let local = SwiftDataLocalStore(modelContainer: container)
            Task { try? await pantry.seedIfEmpty(SampleData.pantry) }
            services.pantry = pantry
            services.recipes = CachingRecipeService(remote: services.recipes, cache: local)
            services.swipeQueue = local
            services.shoppingPersistence = local
        } catch {
            assertionFailure("Could not open the local store: \(error)")
        }
        services.notifier = SystemTimerNotifier()
        services.activities = ActivityKitController()
        return services
    }
}
