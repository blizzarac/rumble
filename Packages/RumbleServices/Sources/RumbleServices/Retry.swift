import Foundation

public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var baseDelay: Duration
    public var multiplier: Double

    public init(maxAttempts: Int, baseDelay: Duration, multiplier: Double) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.multiplier = multiplier
    }

    public static let standard = RetryPolicy(maxAttempts: 4, baseDelay: .milliseconds(300), multiplier: 2)

    /// Delay before the next attempt, given the attempt that just failed (1-based).
    public func delay(afterAttempt attempt: Int) -> Duration {
        baseDelay * pow(multiplier, Double(attempt - 1))
    }
}

/// Retries retryable `ServiceError`s with exponential backoff; any other error is thrown immediately.
public func withRetry<T: Sendable>(
    policy: RetryPolicy = .standard,
    sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    operation: @Sendable () async throws -> T
) async throws -> T {
    var attempt = 1
    while true {
        do {
            return try await operation()
        } catch let error as ServiceError where error.isRetryable && attempt < policy.maxAttempts {
            try await sleep(policy.delay(afterAttempt: attempt))
            attempt += 1
        }
    }
}
