import GRPCCore
import GRPCNIOTransportHTTP2
import RumbleServices

public struct BackendConfig: Sendable {
    public var host: String
    public var port: Int
    public var useTLS: Bool

    public init(host: String, port: Int, useTLS: Bool = true) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
    }
}

/// One long-lived HTTP/2 connection to the backend, shared by every service and
/// multiplexing all calls. Created once at launch.
public final class GRPCBackend: Sendable {
    typealias Client = GRPCCore.GRPCClient<HTTP2ClientTransport.TransportServices>

    let client: Client
    let auth: AuthSession
    private let pipeline: CallPipeline
    private let connection: Task<Void, Never>

    public init(config: BackendConfig, auth: AuthSession) throws {
        let transport = try HTTP2ClientTransport.TransportServices(
            target: .dns(host: config.host, port: config.port),
            transportSecurity: config.useTLS ? .tls : .plaintext,
            config: .defaults { config in
                // Pings every ~30 s so the connection survives idle periods.
                config.connection.keepalive = .init(time: .seconds(30), timeout: .seconds(10), allowWithoutCalls: true)
            }
        )
        let client = Client(transport: transport)
        self.client = client
        self.auth = auth
        self.pipeline = CallPipeline(auth: auth)
        self.connection = Task { try? await client.runConnections() }
    }

    deinit {
        client.beginGracefulShutdown()
        connection.cancel()
    }

    public var deck: any DeckService { GRPCDeckService(backend: self) }
    public var recipes: any RecipeService { GRPCRecipeService(backend: self) }
    public var plans: any PlanService { GRPCPlanService(backend: self) }
    public var pantry: any PantryService { GRPCPantryService(backend: self) }

    static func metadata(token: String) -> Metadata {
        var metadata = Metadata()
        metadata.addString("Bearer \(token)", forKey: "authorization")
        return metadata
    }

    /// A unary call: valid token in the metadata, a deadline, and backoff on `unavailable` / `deadlineExceeded`.
    func unary<T: Sendable>(
        deadline: Duration = CallDeadline.standard,
        _ operation: @escaping @Sendable (Metadata) async throws -> T
    ) async throws -> T {
        try await pipeline.run(deadline: deadline) { token in
            do {
                return try await operation(Self.metadata(token: token))
            } catch {
                throw mapRPCError(error)
            }
        }
    }

    /// A streaming call: token handling only. Retrying mid-stream would replay messages, so the caller decides.
    func authenticated<T: Sendable>(_ operation: @escaping @Sendable (Metadata) async throws -> T) async throws -> T {
        try await withAuth(auth) { token in
            do {
                return try await operation(Self.metadata(token: token))
            } catch {
                throw mapRPCError(error)
            }
        }
    }
}
