import Foundation
import ImageIO
import UIKit
import PhotosUI
import SwiftUI

/// Native photo search against the app's authenticated, pre-indexed catalogue.
/// Only the query photo goes to our own image service; no external AI API.
actor CatalogueImageSearch {
    struct Match: Decodable, Sendable {
        let id: String
        let similarity: Double
        let decision: String?
        let jevProbability: Double?
        enum CodingKeys: String, CodingKey {
            case id, similarity, decision
            case jevProbability = "jev_probability"
        }
    }
    struct Result: Decodable, Sendable {
        let matches: [Match]
        let checked: Int
        let total: Int
        let skipped: Int
        let decisionSource: String?
        enum CodingKeys: String, CodingKey {
            case matches, checked, total, skipped
            case decisionSource = "decision_source"
        }
    }
    enum Failure: LocalizedError {
        case invalidImage, tooLarge, message(String)
        var errorDescription: String? {
            switch self {
            case .invalidImage: "Choose a readable photo of the jewellery."
            case .tooLarge: "Choose a photo smaller than 10 MB."
            case .message(let message): message
            }
        }
    }
    static let maximumBytes = 10 * 1024 * 1024
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        self.session = URLSession(configuration: configuration)
    }

    static func thumbnail(_ data: Data) throws -> CGImage {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 50_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { throw Failure.invalidImage }
        return image
    }

    func search(photo: Data, category: String, allowedIDs: Set<String>) async throws -> Result {
        try Task.checkCancellation()
        guard !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.message("Select a jewellery category.")
        }
        let auth = try await SupabaseManager.client.auth.session
        let accessToken = auth.accessToken
        let url = AppConfig.aiPipelineURL.appending(path: "/api/retailer/image-search")
        let boundary = "JewelImageSearch-\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"jewellery_type\"\r\n\r\n\(category)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"reference.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
        body.append(photo)
        append("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 {
                throw Failure.message("The image search service needs an update. Please try again after the service is deployed.")
            }
            struct ErrorBody: Decodable { let detail: String }
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail
                ?? "Image search is temporarily unavailable. Please try again."
            throw Failure.message(message)
        }
        let result = try JSONDecoder().decode(Result.self, from: data)
        // Render only products from this screen's authorized marketplace
        // snapshot, and keep the server's ranked order. Searching never saves.
        return Result(matches: Array(result.matches.filter {
            guard allowedIDs.contains($0.id), $0.similarity.isFinite else { return false }
            if result.decisionSource == "jev" {
                guard $0.decision == "similar", let probability = $0.jevProbability else { return false }
                return probability.isFinite && (0...1).contains(probability)
            }
            return $0.similarity >= 0.90
        }.prefix(20)), checked: result.checked, total: result.total, skipped: result.skipped,
           decisionSource: result.decisionSource)
    }
}

@MainActor @Observable
final class CatalogueImageSearchModel {
    private let engine = CatalogueImageSearch()
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var photo: Data?
    var preview: UIImage?
    var matchIDs: [String]?
    var isSearching = false
    var isReading = false
    var checked = 0
    var total = 0
    var skipped = 0
    var error: String?

    func read(_ item: PhotosPickerItem) {
        reset(clearPhoto: true)
        isReading = true
        let token = generation
        task = Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw CatalogueImageSearch.Failure.invalidImage
                }
                try Task.checkCancellation()
                let image = try CatalogueImageSearch.thumbnail(data)
                guard token == generation else { return }
                let previewImage = UIImage(cgImage: image)
                guard let jpeg = previewImage.jpegData(compressionQuality: 0.92) else {
                    throw CatalogueImageSearch.Failure.invalidImage
                }
                photo = jpeg
                preview = previewImage
                isReading = false
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isReading = false
            }
        }
    }

    func reset(clearPhoto: Bool = false) {
        task?.cancel()
        task = nil
        generation = UUID()
        matchIDs = nil
        isSearching = false
        isReading = false
        checked = 0
        total = 0
        skipped = 0
        error = nil
        if clearPhoto { photo = nil; preview = nil }
    }

    func search(_ products: [Product], category: String) {
        reset()
        guard let photo else { return }
        let token = generation
        isSearching = true
        total = products.count
        let allowedIDs = Set(products.map(\.id))
        task = Task {
            do {
                let result = try await engine.search(photo: photo, category: category, allowedIDs: allowedIDs)
                guard token == generation, !Task.isCancelled else { return }
                matchIDs = result.matches.map(\.id)
                checked = result.checked
                total = result.total
                skipped = result.skipped
                isSearching = false
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isSearching = false
            }
        }
    }
}
