import Foundation
import Security

public struct AuthToken: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public protocol TokenStore: Sendable {
    func load() async -> AuthToken?
    func save(_ token: AuthToken) async
    func clear() async
}

public protocol TokenRefresher: Sendable {
    /// Throws `ServiceError.unauthenticated` when the refresh token itself is no longer valid.
    func refresh(refreshToken: String) async throws -> AuthToken
}

/// Hands out a valid access token and refreshes it when it is about to expire.
/// Concurrent callers share one refresh. The interceptor in the gRPC layer puts the token in call metadata.
///
/// Open question from the design doc: token type, lifetime and refresh flow are still to be agreed.
public actor AuthSession {
    private let store: any TokenStore
    private let refresher: any TokenRefresher
    private let now: @Sendable () -> Date
    private let leeway: TimeInterval
    private var refreshTask: Task<AuthToken, Error>?

    public init(
        store: any TokenStore,
        refresher: any TokenRefresher,
        leeway: TimeInterval = 30,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.refresher = refresher
        self.leeway = leeway
        self.now = now
    }

    public func accessToken() async throws -> String {
        guard let token = await store.load() else { throw ServiceError.unauthenticated }
        if token.expiresAt.timeIntervalSince(now()) > leeway { return token.accessToken }
        return try await refresh(from: token).accessToken
    }

    /// Called after the backend answered `unauthenticated` to `rejected`.
    public func accessToken(afterRejecting rejected: String) async throws -> String {
        guard let token = await store.load() else { throw ServiceError.unauthenticated }
        // Another caller already refreshed while this one was in flight.
        if token.accessToken != rejected { return token.accessToken }
        return try await refresh(from: token).accessToken
    }

    public func signOut() async {
        refreshTask?.cancel()
        refreshTask = nil
        await store.clear()
    }

    private func refresh(from token: AuthToken) async throws -> AuthToken {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { [store, refresher] in
            let fresh = try await refresher.refresh(refreshToken: token.refreshToken)
            await store.save(fresh)
            return fresh
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch let error as ServiceError where error == .unauthenticated {
            await store.clear()
            throw error
        }
    }
}

/// Runs `operation` with a valid token; if the backend rejects it as `unauthenticated`,
/// refreshes once and tries again.
public func withAuth<T: Sendable>(
    _ session: AuthSession,
    operation: @Sendable (String) async throws -> T
) async throws -> T {
    let token = try await session.accessToken()
    do {
        return try await operation(token)
    } catch ServiceError.unauthenticated {
        let fresh = try await session.accessToken(afterRejecting: token)
        return try await operation(fresh)
    }
}

public actor InMemoryTokenStore: TokenStore {
    private var token: AuthToken?

    public init(token: AuthToken? = nil) {
        self.token = token
    }

    public func load() -> AuthToken? { token }
    public func save(_ token: AuthToken) { self.token = token }
    public func clear() { token = nil }
}

/// Keeps the tokens in the keychain.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "com.example.rumble", account: String = "auth-token") {
        self.service = service
        self.account = account
    }

    public func load() async -> AuthToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(AuthToken.self, from: data)
    }

    public func save(_ token: AuthToken) async {
        guard let data = try? JSONEncoder().encode(token) else { return }
        let update = [kSecValueData as String: data]
        if SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public func clear() async {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
