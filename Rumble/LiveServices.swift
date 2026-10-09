import Foundation
import RumbleProto
import RumbleServices
import RumbleState

extension AppServices {
    /// Real on-device storage, notifications and Live Activities.
    ///
    /// The network services are the fakes unless the app is launched with `RUMBLE_BACKEND=host:port`
    /// (plus `RUMBLE_TOKEN`, and `RUMBLE_TLS=0` for a plaintext dev server), which switches them
    /// to the gRPC adapters. A real sign-in flow replaces the env token once the auth method is agreed.
    @MainActor
    static func live() -> AppServices {
        // UI tests run on fakes with nothing stored on the device.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return AppServices.fake(streamDelay: .milliseconds(10))
        }
        var services = AppServices.fake()
        useBackendIfConfigured(&services)
        do {
            let container = try RumbleStorage.makeContainer()
            let pantry = SwiftDataPantryService(modelContainer: container)
            let local = SwiftDataLocalStore(modelContainer: container)
            Task { try? await pantry.seedIfEmpty(SampleData.pantry) }
            // The pantry stays local until pantry sync semantics are agreed with the backend.
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

    @MainActor
    private static func useBackendIfConfigured(_ services: inout AppServices) {
        let environment = ProcessInfo.processInfo.environment
        guard let spec = environment["RUMBLE_BACKEND"],
              let config = BackendConfig(parsing: spec, useTLS: environment["RUMBLE_TLS"] != "0")
        else { return }

        let token = AuthToken(
            accessToken: environment["RUMBLE_TOKEN"] ?? "",
            refreshToken: "",
            expiresAt: .distantFuture
        )
        let auth = AuthSession(store: InMemoryTokenStore(token: token), refresher: DevTokenRefresher())
        do {
            let backend = try GRPCBackend(config: config, auth: auth)
            services.deck = backend.deck
            services.recipes = backend.recipes
            services.plans = backend.plans
        } catch {
            assertionFailure("Could not set up the backend: \(error)")
        }
    }
}

/// Placeholder until the token refresh flow is agreed: an expired dev token is simply rejected.
private struct DevTokenRefresher: TokenRefresher {
    func refresh(refreshToken: String) async throws -> AuthToken {
        throw ServiceError.unauthenticated
    }
}
