import Foundation

/// Explicit per-call deadlines from the design doc.
public enum CallDeadline {
    public static let swipe: Duration = .seconds(2)
    public static let standard: Duration = .seconds(5)
}

/// Fails with `ServiceError.deadlineExceeded` when `operation` takes longer than `deadline`.
/// The operation is cancelled; it must honour cancellation for the call to actually return early
/// (gRPC calls do).
public func withDeadline<T: Sendable>(
    _ deadline: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: deadline)
            throw ServiceError.deadlineExceeded
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw ServiceError.failed("no result") }
        return result
    }
}

/// What every unary call goes through: a valid token, a deadline, and backoff on
/// `unavailable` / `deadlineExceeded`. The gRPC adapters pass the token on as call metadata.
public struct CallPipeline: Sendable {
    public let auth: AuthSession
    public let retry: RetryPolicy

    public init(auth: AuthSession, retry: RetryPolicy = .standard) {
        self.auth = auth
        self.retry = retry
    }

    public func run<T: Sendable>(
        deadline: Duration = CallDeadline.standard,
        _ operation: @escaping @Sendable (_ accessToken: String) async throws -> T
    ) async throws -> T {
        try await withRetry(policy: retry) {
            try await withAuth(auth) { token in
                try await withDeadline(deadline) { try await operation(token) }
            }
        }
    }
}
