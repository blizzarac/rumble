import RumbleServices
import RumbleState

extension AppServices {
    /// Real on-device storage and notifications. The network services are still the fakes
    /// until the gRPC adapters over RumbleProto exist.
    @MainActor
    static func live() -> AppServices {
        var services = AppServices.fake()
        do {
            let container = try RumbleStorage.makeContainer()
            let pantry = SwiftDataPantryService(modelContainer: container)
            Task { try? await pantry.seedIfEmpty(SampleData.pantry) }
            services.pantry = pantry
        } catch {
            assertionFailure("Could not open the local store: \(error)")
        }
        services.notifier = SystemTimerNotifier()
        return services
    }
}
