import Foundation
import Supabase

/// Client for the JewelIndia backend endpoints that genuinely require a server.
///
/// The web app's `/api/auth/*` routes use `SUPABASE_SERVICE_ROLE_KEY` for work
/// the anon key cannot do — enumerating users, keeping OTP rate-limit state,
/// and counting referral-link redemptions. Those endpoints are called here
/// exactly as the web calls them, at the same host, with the same JSON shapes.
/// Everything else runs on-device against Supabase directly.
enum JewelAPI {

    /// Errors carry the server's message verbatim so the UI can show the same
    /// copy the web shows.
    struct APIError: LocalizedError {
        let status: Int
        let message: String
        /// `send-otp` sets these on its 429 branches.
        var locked: Bool = false
        var lockedUntil: Date?
        var cooldown: Bool = false
        var waitSeconds: Int?

        var errorDescription: String? { message }
    }

    /// A session that keeps cookies, so the Supabase auth cookies the Next
    /// server sets survive across the signup sequence the way a browser's do.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = .shared
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    // MARK: - B1 · POST /api/auth/check-user

    struct CheckUserResponse: Decodable, Sendable {
        let exists: Bool
        let provider: String?
        let isEmail: Bool
        let isPhone: Bool
    }

    /// Existence + provider probe. Needs the service role (`admin.listUsers`),
    /// so it must stay server-side. Unauthenticated.
    static func checkUser(identity: String) async throws -> CheckUserResponse {
        try await post("/api/auth/check-user", body: ["identity": identity])
    }

    // MARK: - B2 · POST /api/auth/send-otp

    struct SendOTPResponse: Decodable, Sendable {
        let success: Bool
        let remainingResends: Int?
        let lastSentAt: String?
    }

    /// Sends the 8-digit OTP. The route owns the rate-limit state
    /// (30 s cooldown, 5 resends, 24 h lockout) in `otp_rate_limits` via the
    /// service role — calling Supabase directly from the device would bypass
    /// all of it, so this always goes to the server.
    static func sendOTP(identity: String) async throws -> SendOTPResponse {
        try await post("/api/auth/send-otp", body: ["identity": identity])
    }

    // MARK: - B3 · POST /api/auth/verify-otp

    struct VerifyOTPResponse: Decodable, Sendable {
        let success: Bool
        let userId: String?
        let isNewUser: Bool
        let userRole: UserRole?
    }

    /// Verifies the OTP **and adopts the resulting session locally**.
    ///
    /// The route verifies against Supabase on a cookie-bound server client. Its JSON
    /// body carries no tokens — they come back as `Set-Cookie`. We read them
    /// out via `SSRSessionBridge` and install them with `auth.setSession`, so
    /// the referral bookkeeping still happens *and* the app ends up holding a
    /// genuine Keychain session for every later RLS-scoped query.
    static func verifyOTP(
        identity: String,
        token: String,
        referralCode: String?
    ) async throws -> VerifyOTPResponse {
        var body: [String: Any] = ["identity": identity, "token": token]
        body["referralCode"] = referralCode ?? NSNull()

        let (data, http) = try await raw("/api/auth/verify-otp", body: body)
        try throwIfError(data: data, http: http)

        let decoded = try decoder.decode(VerifyOTPResponse.self, from: data)

        if let tokens = SSRSessionBridge.tokens(from: http, url: http.url ?? AppConfig.siteURL) {
            _ = try? await SupabaseManager.client.auth.setSession(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken
            )
        }

        return decoded
    }

    /// True once the OTP response has produced a usable local session.
    static var hasLocalSession: Bool {
        SupabaseManager.client.auth.currentSession != nil
    }

    // MARK: - Retailer invitations

    struct RetailerInvitation: Decodable, Sendable {
        let code: String
        let link: URL
        let expiresAt: String

        enum CodingKeys: String, CodingKey {
            case code, link
            case expiresAt = "expires_at"
        }
    }

    struct ClaimInvitationResponse: Decodable, Sendable {
        let success: Bool
        let replayed: Bool?
    }

    struct RetailerMarketplaceResponse: Decodable, Sendable {
        let products: [Product]
        let selectedProductIDs: [String]

        enum CodingKeys: String, CodingKey {
            case products
            case selectedProductIDs = "selected_product_ids"
        }
    }

    struct SuccessResponse: Decodable, Sendable {
        let success: Bool
    }

    struct SupplierSummary: Decodable, Sendable {
        let businessName: String?
        let fullName: String?
        let city: String?
        let state: String?

        enum CodingKeys: String, CodingKey {
            case businessName = "business_name"
            case fullName = "full_name"
            case city, state
        }

        var displayName: String {
            businessName?.trimmed.nilIfEmpty
                ?? fullName?.trimmed.nilIfEmpty
                ?? "Wholesaler"
        }
    }

    struct CreateOrderResponse: Decodable, Sendable {
        let success: Bool
        let data: [Order]
        let suppliers: [String: SupplierSummary]
    }

    struct RetailerOrdersResponse: Decodable, Sendable {
        let orders: [Order]
        let products: [String: Product]
        let suppliers: [String: SupplierSummary]
    }

    /// Generates a database-backed, single-use invitation for the signed-in
    /// verified wholesaler. Codes are never invented on-device.
    static func createRetailerInvitation() async throws -> RetailerInvitation {
        try await authenticatedPost(
            "/api/referral/generate",
            body: ["source": "ios"]
        )
    }

    /// Claims the invitation after the retailer onboarding row exists. The
    /// server performs the row locks and enforces one inviter per retailer.
    @discardableResult
    static func claimRetailerInvitation(code: String) async throws -> ClaimInvitationResponse {
        try await authenticatedPost(
            "/api/referral/claim",
            body: ["code": code]
        )
    }

    static func fetchRetailerMarketplace() async throws -> RetailerMarketplaceResponse {
        try await authenticatedGet("/api/retailer/marketplace")
    }

    static func setRetailerSelection(productID: String, selected: Bool) async throws {
        let _: SuccessResponse = try await authenticatedPost(
            "/api/retailer/your-taste",
            body: ["product_id": productID, "selected": selected]
        )
    }

    static func createRetailerOrder(
        productID: String,
        quantity: Int,
        notes: String
    ) async throws -> CreateOrderResponse {
        try await authenticatedPost(
            "/api/orders/create",
            body: [
                "items": [[
                    "product_id": productID,
                    "quantity": quantity,
                    "customization_notes": notes,
                ]],
            ]
        )
    }

    static func fetchRetailerOrders() async throws -> RetailerOrdersResponse {
        try await authenticatedGet("/api/retailer/orders")
    }

    // MARK: - B4 · set password

    /// The web posts `/api/auth/set-password`, which authenticates from the
    /// SSR cookies and then upserts `profiles` with the service role.
    ///
    /// Done on-device instead: `auth.update(password:data:)` is the identical
    /// call the route makes, and the anon key can upsert the caller's own
    /// `profiles` row — which is exactly what `setUserRole` already does with
    /// the anon client on the web. Server validation is mirrored first so the
    /// same input is rejected with the same message.
    @discardableResult
    static func setPassword(_ password: String, role: UserRole) async throws -> Bool {
        guard !password.isEmpty else {
            throw APIError(status: 400, message: "Password is required.")
        }
        guard Credentials.meetsServerPasswordRule(password) else {
            throw APIError(
                status: 400,
                message: "Password must be at least 8 characters and include 1 uppercase, 1 lowercase, 1 number, and 1 special character."
            )
        }

        let auth = SupabaseManager.client.auth
        guard let user = auth.currentSession?.user else {
            throw APIError(status: 401, message: "Session expired. Please restart the signup process.")
        }

        _ = try await auth.update(
            user: UserAttributes(password: password, data: ["role": .string(role.rawValue)])
        )

        // Mirrors the route's `profiles` upsert. A failure here is logged and
        // swallowed on the web too, so it must not fail the flow.
        struct ProfileRow: Encodable {
            let id: String
            let email: String?
            let role: String
        }
        let row = ProfileRow(
            id: user.id.uuidString,
            email: user.email ?? user.phone,
            role: role.rawValue
        )
        _ = try? await SupabaseManager.client
            .from("profiles")
            .upsert(row, onConflict: "id")
            .execute()

        return true
    }

    // MARK: - Transport

    private static let decoder = JSONDecoder()

    private static func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let (data, http) = try await raw(path, body: body)
        try throwIfError(data: data, http: http)
        return try decoder.decode(T.self, from: data)
    }

    private static func authenticatedPost<T: Decodable>(
        _ path: String,
        body: [String: Any]
    ) async throws -> T {
        let authSession = try await validAuthSession()

        let (data, http) = try await raw(
            path,
            body: body,
            bearerToken: authSession.accessToken
        )
        try throwIfError(data: data, http: http)
        return try decoder.decode(T.self, from: data)
    }

    private static func authenticatedGet<T: Decodable>(_ path: String) async throws -> T {
        let authSession = try await validAuthSession()

        var request = URLRequest(url: AppConfig.siteURL.appending(path: path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: -1, message: "Network error. Please check your connection and try again.")
        }
        try throwIfError(data: data, http: http)
        return try decoder.decode(T.self, from: data)
    }

    /// `currentSession` may contain an expired JWT. The async `session`
    /// property refreshes it when necessary before it is sent to the web API.
    private static func validAuthSession() async throws -> Session {
        do {
            return try await SupabaseManager.client.auth.session
        } catch {
            throw APIError(status: 401, message: "Session expired. Please sign in again.")
        }
    }

    private static func raw(
        _ path: String,
        body: [String: Any],
        bearerToken: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: AppConfig.siteURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: -1, message: "Network error. Please check your connection and try again.")
        }
        return (data, http)
    }

    /// Surfaces the server's own `error` string, plus the `send-otp` rate-limit
    /// metadata the OTP screen needs to drive its lockout UI.
    private static func throwIfError(data: Data, http: HTTPURLResponse) throws {
        guard !(200..<300).contains(http.statusCode) else { return }

        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = object?["error"] as? String ?? "Something went wrong. Please try again."

        var lockedUntil: Date?
        if let iso = object?["lockedUntil"] as? String {
            lockedUntil = ISO8601DateFormatter.jewel.date(from: iso)
        }

        throw APIError(
            status: http.statusCode,
            message: message,
            locked: object?["locked"] as? Bool ?? false,
            lockedUntil: lockedUntil,
            cooldown: object?["cooldown"] as? Bool ?? false,
            waitSeconds: object?["waitSeconds"] as? Int
        )
    }
}

extension ISO8601DateFormatter {
    /// Supabase / Next emit ISO-8601 with fractional seconds.
    static let jewel: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
