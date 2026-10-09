import Foundation
import Supabase
import UIKit

public enum ManufacturingAPI {

    public struct ManufacturingError: LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }

        public init(_ message: String) {
            self.message = message
        }
    }

    private static var baseURL: URL {
        #if DEBUG && targetEnvironment(simulator)
        if let testURL = simulatorTestURL { return testURL }
        #endif
        return AppConfig.aiPipelineURL
    }

    #if DEBUG && targetEnvironment(simulator)
    // Explicit loopback-only integration harness; excluded from physical phones
    // and release builds. It cannot redirect credentials to another host.
    private static var simulatorTestURL: URL? {
        guard let raw = ProcessInfo.processInfo.environment["JEWEL_MFG_TEST_URL"],
              let url = URL(string: raw), url.scheme == "http",
              url.host == "127.0.0.1", url.port == 8810 else { return nil }
        return url
    }
    #endif

    private static func authorizedRequest(
        _ url: URL,
        method: String = "GET",
        idempotencyKey: String? = nil
    ) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        #if DEBUG && targetEnvironment(simulator)
        if simulatorTestURL != nil,
           let fixtureToken = ProcessInfo.processInfo.environment["JEWEL_MFG_TEST_TOKEN"] {
            request.setValue("Bearer \(fixtureToken)", forHTTPHeaderField: "Authorization")
            if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
            return request
        }
        #endif

        guard let session = try? await SupabaseManager.client.auth.session else {
            throw ManufacturingError("Please sign in to continue.")
        }
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        return request
    }

    // MARK: - Asset Upload

    public struct AssetUploadResponse: Decodable {
        public let ok: Bool
        public let assetID: UUID
        public let previewURL: String?
        public let width: Int?
        public let height: Int?
        public let byteSize: Int?

        enum CodingKeys: String, CodingKey {
            case ok
            case assetID = "asset_id"
            case previewURL = "preview_url"
            case width, height
            case byteSize = "byte_size"
        }
    }

    public static func uploadAsset(imageData: Data) async throws -> AssetUploadResponse {
        let url = baseURL.appending(path: "/api/retailer/manufacturing-assets")
        var request = try await authorizedRequest(url, method: "POST")

        let boundary = "JewelMfgAsset-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"reference.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManufacturingError("Failed to reach server.")
        }

        guard (200..<300).contains(http.statusCode) else {
            struct ErrorResponse: Decodable { let detail: String? }
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.detail
                ?? "Image upload failed with status \(http.statusCode)."
            throw ManufacturingError(msg)
        }

        return try JSONDecoder().decode(AssetUploadResponse.self, from: data)
    }

    // MARK: - Retailer Endpoints

    public struct CreateRequestResponse: Decodable {
        public let ok: Bool
        public let requestID: UUID?
        public let state: String?
        public let activeOfferID: UUID?
        public let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case ok, state
            case requestID = "request_id"
            case activeOfferID = "active_offer_id"
            case expiresAt = "expires_at"
        }
    }

    public static func createRequest(
        params: CreateManufacturingRequestParams,
        idempotencyKey: String = UUID().uuidString
    ) async throws -> CreateRequestResponse {
        let url = baseURL.appending(path: "/api/retailer/manufacturing-requests")
        var request = try await authorizedRequest(url, method: "POST", idempotencyKey: idempotencyKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(params)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManufacturingError("Invalid server response.")
        }

        guard (200..<300).contains(http.statusCode) else {
            struct ErrorResponse: Decodable { let detail: String? }
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.detail
                ?? "Request creation failed."
            throw ManufacturingError(msg)
        }

        return try JSONDecoder().decode(CreateRequestResponse.self, from: data)
    }

    public struct ListRequestsResponse: Decodable {
        public let ok: Bool
        public let requests: [ManufacturingRequest]
        public let serverTime: String?

        enum CodingKeys: String, CodingKey {
            case ok, requests
            case serverTime = "server_time"
        }
    }

    public static func fetchRetailerRequests(status: String? = nil) async throws -> [ManufacturingRequest] {
        var components = URLComponents(url: baseURL.appending(path: "/api/retailer/manufacturing-requests"), resolvingAgainstBaseURL: true)!
        if let status {
            components.queryItems = [URLQueryItem(name: "status", value: status)]
        }
        let request = try await authorizedRequest(components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ManufacturingError("Failed to fetch manufacturing requests.")
        }

        let decoded = try JSONDecoder().decode(ListRequestsResponse.self, from: data)
        return decoded.requests
    }

    public struct RequestDetailResponse: Decodable {
        public let ok: Bool
        public let request: ManufacturingRequest
        public let serverTime: String?

        enum CodingKeys: String, CodingKey {
            case ok, request
            case serverTime = "server_time"
        }
    }

    public static func fetchRetailerRequestDetail(id: UUID) async throws -> ManufacturingRequest {
        let url = baseURL.appending(path: "/api/retailer/manufacturing-requests/\(id.uuidString)")
        let request = try await authorizedRequest(url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ManufacturingError("Failed to load request details.")
        }

        let decoded = try JSONDecoder().decode(RequestDetailResponse.self, from: data)
        return decoded.request
    }

    public static func cancelRequest(id: UUID) async throws {
        let url = baseURL.appending(path: "/api/retailer/manufacturing-requests/\(id.uuidString)/cancel")
        let request = try await authorizedRequest(url, method: "POST")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            struct ErrorResponse: Decodable { let detail: String? }
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.detail
                ?? "Cancellation failed."
            throw ManufacturingError(msg)
        }
    }

    public static func awardQuote(requestID: UUID, quoteID: UUID) async throws {
        let url = baseURL.appending(path: "/api/retailer/manufacturing-requests/\(requestID.uuidString)/award")
        var request = try await authorizedRequest(url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Payload: Encodable { let quote_id: UUID }
        request.httpBody = try JSONEncoder().encode(Payload(quote_id: quoteID))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { let detail: String? }
            throw ManufacturingError((try? JSONDecoder().decode(Failure.self, from: data))?.detail ?? "Could not select this quote. Refresh the enquiry and try again.")
        }
    }

    // MARK: - Wholesaler Endpoints

    public struct ListOffersResponse: Decodable {
        public let ok: Bool
        public let offers: [ManufacturingOffer]
        public let serverTime: String?

        enum CodingKeys: String, CodingKey {
            case ok, offers
            case serverTime = "server_time"
        }
    }

    public static func fetchWholesalerOffers(status: String? = nil) async throws -> [ManufacturingOffer] {
        var components = URLComponents(url: baseURL.appending(path: "/api/wholesaler/manufacturing-offers"), resolvingAgainstBaseURL: true)!
        if let status {
            components.queryItems = [URLQueryItem(name: "status", value: status)]
        }
        let request = try await authorizedRequest(components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ManufacturingError("Failed to fetch offers.")
        }

        let decoded = try JSONDecoder().decode(ListOffersResponse.self, from: data)
        return decoded.offers
    }

    public struct OfferDetailResponse: Decodable {
        public let ok: Bool
        public let offer: ManufacturingOffer
        public let serverTime: String?

        enum CodingKeys: String, CodingKey {
            case ok, offer
            case serverTime = "server_time"
        }
    }

    public static func fetchWholesalerOfferDetail(id: UUID) async throws -> ManufacturingOffer {
        let url = baseURL.appending(path: "/api/wholesaler/manufacturing-offers/\(id.uuidString)")
        let request = try await authorizedRequest(url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ManufacturingError("Failed to load offer.")
        }

        let decoded = try JSONDecoder().decode(OfferDetailResponse.self, from: data)
        return decoded.offer
    }

    public static func acceptOffer(
        id: UUID,
        params: AcceptOfferQuoteParams,
        parallel: Bool = false,
        idempotencyKey: String = UUID().uuidString
    ) async throws {
        let url = baseURL.appending(path: "/api/wholesaler/manufacturing-offers/\(id.uuidString)/\(parallel ? "quotes" : "accept")")
        var request = try await authorizedRequest(url, method: "POST", idempotencyKey: idempotencyKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(params)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            struct ErrorResponse: Decodable { let detail: String? }
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.detail
                ?? "Acceptance failed."
            throw ManufacturingError(msg)
        }
    }

    public static func declineOffer(
        id: UUID,
        reason: String? = nil,
        idempotencyKey: String = UUID().uuidString
    ) async throws {
        let url = baseURL.appending(path: "/api/wholesaler/manufacturing-offers/\(id.uuidString)/decline")
        var request = try await authorizedRequest(url, method: "POST", idempotencyKey: idempotencyKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct DeclinePayload: Encodable { let reason: String? }
        request.httpBody = try JSONEncoder().encode(DeclinePayload(reason: reason))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            struct ErrorResponse: Decodable { let detail: String? }
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.detail
                ?? "Decline failed."
            throw ManufacturingError(msg)
        }
    }

    // MARK: - Device Registration

    public static func registerDeviceToken(_ token: String, environment: String = "production") async throws {
        let url = baseURL.appending(path: "/api/devices/register")
        var request = try await authorizedRequest(url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct RegisterPayload: Encodable {
            let device_token: String
            let environment: String
        }
        request.httpBody = try JSONEncoder().encode(RegisterPayload(device_token: token, environment: environment))
        _ = try? await URLSession.shared.data(for: request)
    }
}
