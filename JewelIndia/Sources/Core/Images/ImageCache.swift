import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Downloads remote images once, bounds network concurrency, decodes them no
/// larger than they're drawn on background executors, and keeps them in memory
/// and on disk with reliable cache key derivation.
actor ImageCache {
    static let shared = ImageCache()

    /// Decoded images in memory. Cost is bytes, so the limit is a real memory budget.
    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()

    private let directory: URL
    private let session: URLSession

    /// In-flight decode tasks keyed by "\(stableKey)|\(maxPixels)".
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    /// Shared raw data downloads keyed by stableKey (stripping volatile auth only).
    /// Prevents duplicate concurrent network requests when multiple views or sizes
    /// ask for the same image at once.
    private var inFlightDownloads: [String: Task<Data, Error>] = [:]

    /// Bounded download concurrency (maximum 6 concurrent transfers).
    private static let maxConcurrentDownloads = 6
    private var activeDownloads = 0
    private var downloadWaiters: [CheckedContinuation<Void, Never>] = []

    /// Invalidation generation counter for logout race prevention.
    private var currentGeneration = 0

    /// Disk cache maximum size.
    private static let diskLimitBytes = 200 * 1024 * 1024

    private static let volatileQueryParamNames: Set<String> = [
        "token", "access_token", "auth", "signature", "sig",
        "expires", "awsaccesskeyid",
        "x-amz-algorithm", "x-amz-credential", "x-amz-date",
        "x-amz-expires", "x-amz-signedheaders", "x-amz-signature",
        "x-amz-security-token",
    ]

    init(session: URLSession = .shared) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("JewelImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The image at `url`, drawn no larger than `maxPixels` on its longest edge.
    func image(for url: URL, maxPixels: Int) -> Task<UIImage, Error> {
        let key = Self.cacheKey(for: url, maxPixels: maxPixels)

        if let cached = memory.object(forKey: key as NSString) {
            return Task { cached }
        }
        if let existing = inFlight[key] {
            return existing
        }

        let generation = currentGeneration
        let task = Task<UIImage, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.load(url: url, key: key, maxPixels: maxPixels, generation: generation)
        }
        inFlight[key] = task
        return task
    }

    private func load(url: URL, key: String, maxPixels: Int, generation: Int) async throws -> UIImage {
        defer { inFlight[key] = nil }

        let file = directory.appendingPathComponent(Self.fileName(for: key))
        // 1. Check disk cache for pre-decoded variant
        if let data = try? Data(contentsOf: file) {
            if let image = await decodeOffMainThread(data: data, maxPixels: maxPixels) {
                if generation == currentGeneration {
                    remember(image, key: key)
                    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
                }
                return image
            }
        }

        // 2. Obtain raw image data via deduplicated and concurrency-bounded download
        let rawData = try await fetchSharedData(for: url, generation: generation)

        // 3. Decode off the main thread & actor
        guard let image = await decodeOffMainThread(data: rawData, maxPixels: maxPixels) else {
            throw URLError(.cannotDecodeContentData)
        }

        if generation == currentGeneration {
            try? rawData.write(to: file, options: .atomic)
            remember(image, key: key)
        }
        return image
    }

    private func fetchSharedData(for url: URL, generation: Int) async throws -> Data {
        let downloadKey = Self.stableKey(for: url)

        if let existing = inFlightDownloads[downloadKey] {
            return try await existing.value
        }

        let task = Task<Data, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            await self.acquireDownloadSlot()
            defer {
                Task { [weak self] in await self?.releaseDownloadSlot() }
            }

            try Task.checkCancellation()
            let (data, response) = try await self.session.data(from: url)
            try Task.checkCancellation()

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }

        inFlightDownloads[downloadKey] = task
        defer { inFlightDownloads[downloadKey] = nil }

        return try await task.value
    }

    private func acquireDownloadSlot() async {
        if activeDownloads < Self.maxConcurrentDownloads {
            activeDownloads += 1
            return
        }
        await withCheckedContinuation { continuation in
            downloadWaiters.append(continuation)
        }
    }

    private func releaseDownloadSlot() {
        if !downloadWaiters.isEmpty {
            let next = downloadWaiters.removeFirst()
            next.resume()
        } else {
            activeDownloads = max(0, activeDownloads - 1)
        }
    }

    private func decodeOffMainThread(data: Data, maxPixels: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            Self.decode(data, maxPixels: maxPixels)
        }.value
    }

    private func remember(_ image: UIImage, key: String) {
        let bytes = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: key as NSString, cost: bytes)
    }

    /// Drop the oldest files once the folder grows past its limit.
    func trimDisk() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return }

        let sized = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize,
                  let date = values.contentModificationDate else { return nil }
            return (url, size, date)
        }
        var total = sized.reduce(0) { $0 + $1.1 }
        guard total > Self.diskLimitBytes else { return }

        for (url, size, _) in sized.sorted(by: { $0.2 < $1.2 }) {
            try? FileManager.default.removeItem(at: url)
            total -= size
            if total <= Self.diskLimitBytes { break }
        }
    }

    /// Cancels all pending in-flight tasks and purges memory and disk.
    func clear() {
        currentGeneration += 1
        for (_, task) in inFlight { task.cancel() }
        inFlight.removeAll()

        for (_, task) in inFlightDownloads { task.cancel() }
        inFlightDownloads.removeAll()

        // Resume all waiting continuations to prevent hangs
        let waiters = downloadWaiters
        downloadWaiters.removeAll()
        activeDownloads = 0
        for waiter in waiters { waiter.resume() }

        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Pure helpers

    /// Explicit stable asset identity:
    /// Strips volatile authentication/signature parameters that change hourly,
    /// but strictly preserves image transform parameters (width, quality, format, etc.)
    /// and revision/version tokens.
    static func stableKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.fragment = nil

        if let queryItems = components.queryItems, !queryItems.isEmpty {
            let retained = queryItems.filter { item in
                !volatileQueryParamNames.contains(item.name.lowercased())
            }

            if retained.isEmpty {
                components.query = nil
            } else {
                // Stable ordering to prevent parameter order cache misses
                components.queryItems = retained.sorted { a, b in
                    if a.name == b.name {
                        return (a.value ?? "") < (b.value ?? "")
                    }
                    return a.name < b.name
                }
            }
        }

        return components.url?.absoluteString ?? url.absoluteString
    }

    static func cacheKey(for url: URL, maxPixels: Int) -> String {
        "\(stableKey(for: url))|\(maxPixels)"
    }

    static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Decode to at most `maxPixels` on the longest edge, without ever holding
    /// the full-size bitmap in memory.
    nonisolated static func decode(_ data: Data, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 1)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}
