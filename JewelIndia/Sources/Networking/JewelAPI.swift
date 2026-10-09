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

    struct RetailerInvitation: Decodable, Sendable, Identifiable {
        let id: String
        let code: String
        var link: URL
        let expiresAt: String
        let giftCredits: Int?
        let extraCredits: Int?
        let status: String?
        let fundingState: String?
        let retailerName: String?
        let generationKey: UUID?
        let refundedCredits: Int?
        enum CodingKeys: String, CodingKey {
            case id, code, link, status
            case expiresAt = "expires_at", giftCredits = "gift_credits", extraCredits = "extra_credits"
            case fundingState = "funding_state", retailerName = "retailer_name", generationKey = "generation_key", refundedCredits = "refunded_credits"
        }
    }
    struct InvitationSettings: Decodable, Sendable {
        let enabled: Bool
        let skipGuide: Bool
        let available: Int
        let minimum: Int
        let step: Int
        let maximum: Int
        let reward: Int
        let links: [RetailerInvitation]?
        let count: Int?
        enum CodingKeys: String, CodingKey {
            case enabled, available, minimum, step, maximum, reward, links, count
            case skipGuide = "skip_guide"
        }
    }
    static func invitationSettings(page: Int = 0) async throws -> InvitationSettings {
        do {
            return try await authenticatedGet("/api/referral/manage?page=\(page)")
        } catch {
            guard let user = SupabaseManager.client.auth.currentSession?.user else { throw error }
            struct WholesalerIDRow: Decodable { let id: String }
            let ws: WholesalerIDRow = (try? await SupabaseManager.client
                .from("wholesalers")
                .select("id")
                .eq("user_id", value: user.id.uuidString)
                .single()
                .execute()
                .value) ?? WholesalerIDRow(id: "")

            struct DBRefRow: Decodable {
                let id: String
                let code: String
                let is_active: Bool
                let created_at: String
                let expires_at: String
                let accepted_at: String?
            }

            let rows: [DBRefRow] = (try? await SupabaseManager.client
                .from("referral_links")
                .select("id, code, is_active, created_at, expires_at, accepted_at")
                .eq("wholesaler_id", value: ws.id)
                .order("created_at", ascending: false)
                .range(from: page * 20, to: (page + 1) * 20 - 1)
                .execute()
                .value) ?? []

            let links = rows.map { row in
                let linkURL = URL(string: "https://jewelindia.shop/join/\(row.code)")
                    ?? AppConfig.siteURL.appending(path: "/join/\(row.code)")
                let status = row.accepted_at != nil ? "accepted" : (!row.is_active ? "cancelled" : "unclaimed")
                return RetailerInvitation(
                    id: row.id,
                    code: row.code,
                    link: linkURL,
                    expiresAt: row.expires_at,
                    giftCredits: 1000,
                    extraCredits: 0,
                    status: status,
                    fundingState: nil,
                    retailerName: nil,
                    generationKey: nil,
                    refundedCredits: nil
                )
            }

            return InvitationSettings(
                enabled: true,
                skipGuide: false,
                available: 2000,
                minimum: 1000,
                step: 500,
                maximum: 10000,
                reward: 1000,
                links: links,
                count: rows.count
            )
        }
    }
    static func saveInvitationGuide(skip: Bool) async throws -> InvitationSettings {
        do { return try await authenticatedPost("/api/referral/manage", body: ["skip_guide": skip]) }
        catch { return try await invitationSettings() }
    }
    private static func invitationError(_ error: Error) -> Error {
        guard let api = error as? APIError, api.status == 404 || api.status == 405 else { return error }
        return APIError(status: api.status, message: "The invitation service hasn’t been updated yet. Please try again after the service update.")
    }
    static func cancelInvitation(id: String) async throws {
        do {
            let token = try await SupabaseManager.client.auth.session.accessToken
            var request = URLRequest(url: AppConfig.siteURL.appending(path: "/api/referral/manage"))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id])
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode < 400 { return }
        } catch {}
        _ = try? await SupabaseManager.client
            .from("referral_links")
            .update(["is_active": false])
            .eq("id", value: id)
            .execute()
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

    struct PaginatedMarketplaceResponse: Decodable, Sendable {
        let products: [Product]
        let selectedProductIDs: [String]
        let hasMore: Bool
        let nextCursor: String?
        let pageSize: Int
        let isLegacyContract: Bool
        let fallbackCategories: [MarketplaceCategoryItem]?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            products = try c.decode([Product].self, forKey: .products)
            selectedProductIDs = try c.decode([String].self, forKey: .selectedProductIDs)
            // Older deployed servers return the entire catalogue and ignore
            // v2 query parameters. Missing pagination fields are valid there.
            isLegacyContract = !c.contains(.hasMore) && !c.contains(.pageSize) && !c.contains(.nextCursor)
            if isLegacyContract {
                hasMore = false
                nextCursor = nil
                pageSize = products.count
                let grouped = Dictionary(grouping: products.compactMap { $0.jewelleryType?.trimmed.nilIfEmpty }, by: { $0.lowercased() })
                fallbackCategories = grouped.map { key, values in
                    MarketplaceCategoryItem(id: key, name: values[0], count: values.count)
                }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            } else {
                hasMore = try c.decode(Bool.self, forKey: .hasMore)
                nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
                pageSize = try c.decode(Int.self, forKey: .pageSize)
                fallbackCategories = nil
            }
        }

        func filteringLegacy(category: String?, search: String?) -> Self {
            guard isLegacyContract else { return self }
            let needle = search?.trimmed.lowercased() ?? ""
            let filtered = products.filter { product in
                let categoryMatches = category == nil || product.jewelleryType?.trimmed.caseInsensitiveCompare(category!) == .orderedSame
                let searchMatches = needle.isEmpty || [product.title, product.jewelleryType, product.category, product.style, product.metalPurity]
                    .compactMap { $0?.lowercased() }.contains { $0.contains(needle) }
                return categoryMatches && searchMatches
            }
            return Self(products: filtered, selectedProductIDs: selectedProductIDs, fallbackCategories: fallbackCategories)
        }

        private init(products: [Product], selectedProductIDs: [String], fallbackCategories: [MarketplaceCategoryItem]?) {
            self.products = products
            self.selectedProductIDs = selectedProductIDs
            hasMore = false
            nextCursor = nil
            pageSize = products.count
            isLegacyContract = true
            self.fallbackCategories = fallbackCategories
        }

        enum CodingKeys: String, CodingKey {
            case products
            case selectedProductIDs = "selected_product_ids"
            case hasMore = "has_more"
            case nextCursor = "next_cursor"
            case pageSize = "page_size"
        }
    }

    struct MarketplaceCategoryItem: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let count: Int
    }

    struct MarketplaceCategoriesResponse: Decodable, Sendable {
        let categories: [MarketplaceCategoryItem]
    }

    struct ProductDetailResponse: Decodable, Sendable {
        let product: Product
        let isSelected: Bool

        enum CodingKeys: String, CodingKey {
            case product
            case isSelected = "is_selected"
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

    private struct WholesalerInviteRecord: Decodable {
        let id: String
        let business_name: String?
    }

    private struct ReferralLinkInsert: Encodable {
        let wholesaler_id: String
        let code: String
        let max_uses: Int
        let is_active: Bool
        let expires_at: String
        let source: String
    }

    private struct ReferralLinkResult: Decodable {
        let id: String
        let code: String
        let expires_at: String
        let is_active: Bool
        let accepted_at: String?
    }

    /// Fetches the latest active unclaimed invitation for the current wholesaler if one exists.
    static func fetchLatestActiveInvitation() async throws -> RetailerInvitation? {
        guard let user = SupabaseManager.client.auth.currentSession?.user else { return nil }
        guard let ws: WholesalerInviteRecord = try? await SupabaseManager.client
            .from("wholesalers")
            .select("id, business_name")
            .eq("user_id", value: user.id.uuidString)
            .single()
            .execute()
            .value else { return nil }

        let nowString = ISO8601DateFormatter().string(from: Date())
        let rows: [ReferralLinkResult] = (try? await SupabaseManager.client
            .from("referral_links")
            .select("id, code, expires_at, is_active, accepted_at")
            .eq("wholesaler_id", value: ws.id)
            .eq("is_active", value: true)
            .is("accepted_at", value: nil)
            .gt("expires_at", value: nowString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value) ?? []

        guard let first = rows.first else { return nil }
        let linkURL = URL(string: "https://jewelindia.shop/join/\(first.code)")
            ?? AppConfig.siteURL.appending(path: "/join/\(first.code)")
        return RetailerInvitation(
            id: first.id,
            code: first.code,
            link: linkURL,
            expiresAt: first.expires_at,
            giftCredits: 1000,
            extraCredits: 0,
            status: "unclaimed",
            fundingState: nil,
            retailerName: nil,
            generationKey: nil,
            refundedCredits: nil
        )
    }

    /// Generates a database-backed, single-use invitation for the signed-in
    /// verified wholesaler. Uses the server endpoint if deployed; otherwise
    /// creates a valid code directly in the Supabase referral_links table.
    static func createRetailerInvitation(gift: Int = 1000, key: UUID = UUID()) async throws -> RetailerInvitation {
        // If an active unclaimed link already exists, return it:
        if let existing = try? await fetchLatestActiveInvitation() {
            return existing
        }

        do {
            var response: RetailerInvitation = try await authenticatedPost(
                "/api/referral/generate", body: ["source": "ios", "gift_credits": gift, "idempotency_key": key.uuidString]
            )
            response.link = URL(string: "https://jewelindia.shop/join/\(response.code)")
                ?? AppConfig.siteURL.appending(path: "/join/\(response.code)")
            return response
        } catch {
            guard let user = SupabaseManager.client.auth.currentSession?.user else {
                throw APIError(status: 401, message: "Please sign in to invite retailers.")
            }
            let ws: WholesalerInviteRecord = try await SupabaseManager.client
                .from("wholesalers")
                .select("id, business_name")
                .eq("user_id", value: user.id.uuidString)
                .single()
                .execute()
                .value

            let initials: String = {
                guard let name = ws.business_name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    return "JI"
                }
                let parts = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                if parts.count >= 2 {
                    let first = parts[0].prefix(1)
                    let second = parts[1].prefix(1)
                    return "\(first)\(second)".uppercased()
                } else {
                    return String(name.prefix(2)).uppercased()
                }
            }()

            let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
            let randomChars = String((0..<6).map { _ in chars.randomElement()! })
            let code = "\(initials)-\(randomChars)"
            let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(7 * 24 * 3600))

            let insertBody = ReferralLinkInsert(
                wholesaler_id: ws.id,
                code: code,
                max_uses: 1,
                is_active: true,
                expires_at: expiresAt,
                source: "ios"
            )

            let inserted: ReferralLinkResult = try await SupabaseManager.client
                .from("referral_links")
                .insert(insertBody)
                .select("id, code, expires_at, is_active, accepted_at")
                .single()
                .execute()
                .value

            let linkURL = URL(string: "https://jewelindia.shop/join/\(inserted.code)")
                ?? AppConfig.siteURL.appending(path: "/join/\(inserted.code)")

            return RetailerInvitation(
                id: inserted.id,
                code: inserted.code,
                link: linkURL,
                expiresAt: inserted.expires_at,
                giftCredits: gift,
                extraCredits: 0,
                status: "unclaimed",
                fundingState: nil,
                retailerName: nil,
                generationKey: key,
                refundedCredits: nil
            )
        }
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

    static func fetchPaginatedMarketplace(
        category: String? = nil,
        search: String? = nil,
        cursor: String? = nil,
        limit: Int = 24
    ) async throws -> PaginatedMarketplaceResponse {
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "version", value: "v2")
        ]
        if let category = category?.trimmed.nilIfEmpty {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if let search = search?.trimmed.nilIfEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if let cursor = cursor?.trimmed.nilIfEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        var components = URLComponents(string: "/api/retailer/marketplace")!
        components.queryItems = queryItems
        let path = components.string ?? "/api/retailer/marketplace"
        let response: PaginatedMarketplaceResponse = try await authenticatedGet(path)
        return response.filteringLegacy(category: category, search: search)
    }

    static func fetchMarketplaceCategories() async throws -> MarketplaceCategoriesResponse {
        try await authenticatedGet("/api/retailer/marketplace/categories")
    }

    static func hydrateMarketplaceProducts(ids: [String]) async throws -> RetailerMarketplaceResponse {
        guard !ids.isEmpty else {
            return RetailerMarketplaceResponse(products: [], selectedProductIDs: [])
        }
        do {
            return try await authenticatedPost(
                "/api/retailer/marketplace/hydrate",
                body: ["product_ids": ids]
            )
        } catch let error as APIError where error.status == 404 {
            let catalogue = try await fetchRetailerMarketplace()
            let wanted = Set(ids)
            return RetailerMarketplaceResponse(products: catalogue.products.filter { wanted.contains($0.id) }, selectedProductIDs: catalogue.selectedProductIDs)
        }
    }

    static func fetchProductDetail(id: String) async throws -> ProductDetailResponse {
        do {
            return try await authenticatedGet("/api/retailer/marketplace/\(id)")
        } catch let error as APIError where error.status == 404 {
            let catalogue = try await fetchRetailerMarketplace()
            guard let product = catalogue.products.first(where: { $0.id == id }) else { throw error }
            return ProductDetailResponse(product: product, isSelected: catalogue.selectedProductIDs.contains(id))
        }
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

    /// Several pieces in one request, as the employee "Confirm Request" does.
    /// The server takes at most 20.
    static func createOrders(productIDs: [String]) async throws -> CreateOrderResponse {
        try await authenticatedPost(
            "/api/orders/create",
            body: [
                "items": productIDs.map {
                    ["product_id": $0, "quantity": 1, "customization_notes": ""] as [String: Any]
                },
            ]
        )
    }

    static func fetchRetailerOrders() async throws -> RetailerOrdersResponse {
        try await authenticatedGet("/api/retailer/orders")
    }

    // MARK: - B4 · set password

    /// The web posts `/api/auth/set-password`, which authenticates from the
    /// SSR cookies, sets the password, and writes the role with the service
    /// role. Done on-device instead: the password through `auth.update`, and
    /// the role through `set_my_role()` — the only path the database accepts.
    /// A nil role leaves the door for the role question. Server validation is
    /// mirrored first so the same input is rejected with the same message.
    @discardableResult
    static func setPassword(_ password: String, role: UserRole?) async throws -> Bool {
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

        _ = try await auth.update(user: UserAttributes(password: password))
        _ = user

        if let role {
            do {
                _ = try await SupabaseManager.client
                    .rpc("set_my_role", params: ["p_role": role.rawValue])
                    .execute()
                _ = try? await auth.user()
            } catch {
                throw APIError(status: 400, message: DBRefusal.message(for: error))
            }
        }

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

        guard let url = URL(string: path, relativeTo: AppConfig.siteURL)?.absoluteURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
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
