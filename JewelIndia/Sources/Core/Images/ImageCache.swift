import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Downloads remote images once, decodes them no larger than they're drawn,
/// and keeps them in memory and on disk.
///
/// Two details do the real work:
///
/// **Keyed by the storage path, not the URL.** Chamak images live in a private
/// bucket and are fetched through signed links whose token changes every hour,
/// so a URL-keyed cache misses on every visit and re-downloads the image. The
/// key is the URL with its query stripped, which is stable for both signed and
/// public links.
///
/// **Decoded to the size shown.** A 2048px photo costs ~16 MB of RAM decoded;
/// a dozen in a grid is enough to make an iPad stutter. `ImageIO` decodes
/// straight to the pixel size the view needs.
actor ImageCache {
    static let shared = ImageCache()

    /// Decoded images. Cost is bytes, so the limit is a real memory budget.
    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()

    private let directory: URL
    private let session: URLSession
    /// One download per key, however many views ask for it at once.
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    /// Oldest files are dropped past this; the variants are tens of KB each,
    /// so this holds thousands of images.
    private static let diskLimitBytes = 200 * 1024 * 1024

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

        let task = Task<UIImage, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.load(url: url, key: key, maxPixels: maxPixels)
        }
        inFlight[key] = task
        return task
    }

    private func load(url: URL, key: String, maxPixels: Int) async throws -> UIImage {
        defer { inFlight[key] = nil }

        let file = directory.appendingPathComponent(Self.fileName(for: key))
        if let data = try? Data(contentsOf: file), let image = Self.decode(data, maxPixels: maxPixels) {
            remember(image, key: key)
            // Keeps the most-used files from being trimmed first.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return image
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let image = Self.decode(data, maxPixels: maxPixels) else {
            throw URLError(.cannotDecodeContentData)
        }
        try? data.write(to: file, options: .atomic)
        remember(image, key: key)
        return image
    }

    private func remember(_ image: UIImage, key: String) {
        let bytes = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: key as NSString, cost: bytes)
    }

    /// Drop the oldest files once the folder grows past its limit. Cheap
    /// enough to call on launch; never touches what is in memory.
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

    /// Everything this cache holds. Used when signing out.
    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Pure helpers

    /// The URL without its query: a signed link's token changes hourly, the
    /// object it points at does not.
    static func stableKey(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
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
