import Foundation

/// Photos stay on a CDN; this loads them with URLSession and keeps them in memory and on disk.
public actor ImageCache {
    public static let shared = ImageCache()

    private let session: URLSession
    private var memory: [URL: Data] = [:]
    private var inFlight: [URL: Task<Data, Error>] = [:]

    /// Pass a session to control caching or stub the network in tests.
    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 300 << 20)
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: configuration)
        }
    }

    public func data(for url: URL) async throws -> Data {
        if let cached = memory[url] { return cached }
        // Concurrent requests for the same photo share one download.
        if let task = inFlight[url] { return try await task.value }
        let session = session
        let task = Task { () throws -> Data in
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ServiceError.failed("image \(url.lastPathComponent)")
            }
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let data = try await task.value
        memory[url] = data
        return data
    }

    /// Warms the cache for cards that are about to appear in the deck. Failures are ignored.
    public func prefetch(_ urls: [URL]) {
        for url in urls where memory[url] == nil && inFlight[url] == nil {
            Task { _ = try? await self.data(for: url) }
        }
    }
}
