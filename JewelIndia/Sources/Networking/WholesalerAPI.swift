import Foundation
import Supabase

/// Data access for the wholesaler surface.
///
/// Almost everything here is a direct Supabase call, because the web's
/// `/api/*` routes for this surface are thin wrappers the anon key can do
/// itself under RLS:
///   • `products` — select is public; insert/update/delete are gated on
///     `auth.uid() = wholesaler_id` (`SUPABASE_SETUP.sql`).
///   • `wholesalers` — own-row select/insert/update (`WHOLESALERS_TABLE.sql`).
///   • `orders` — `wholesalers_own_orders` (`ORDERS_TABLE.sql`).
/// The AI pipeline is a separate Railway service and is called directly, the
/// same way the browser calls it.
enum WholesalerAPI {

    private static var db: SupabaseClient { SupabaseManager.client }

    // MARK: - Wholesaler record

    /// The home screen looks the row up by `email` first and falls back to
    /// `user_id`, matching `app/dashboard/wholesaler/page.jsx`.
    static func fetchWholesaler(userID: UUID, email: String?) async throws -> Wholesaler? {
        if let email, !email.isEmpty {
            let byEmail: [Wholesaler] = try await db.from("wholesalers")
                .select()
                .eq("email", value: email)
                .limit(1)
                .execute()
                .value
            if let row = byEmail.first { return row }
        }
        let byUser: [Wholesaler] = try await db.from("wholesalers")
            .select()
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return byUser.first
    }

    /// Side effect the web performs on first dashboard render. It is what flips
    /// a verified wholesaler from the "submitted" screen to the dashboard on
    /// subsequent logins.
    static func markDashboardVisited(userID: UUID) async {
        struct Patch: Encodable { let has_visited_dashboard: Bool }
        _ = try? await db.from("wholesalers")
            .update(Patch(has_visited_dashboard: true))
            .eq("user_id", value: userID.uuidString)
            .execute()
    }

    // MARK: - Home counts

    /// `select("*", {count:"exact", head:true})` — the row payload is discarded.
    static func countProducts(wholesalerID: UUID) async -> Int {
        await count(from: "products", column: "wholesaler_id", value: wholesalerID.uuidString)
    }

    static func countPendingOrders(wholesalerID: UUID) async -> Int {
        do {
            let response = try await db.from("orders")
                .select("*", head: true, count: .exact)
                .eq("wholesaler_id", value: wholesalerID.uuidString)
                .eq("status", value: OrderStatus.pending.rawValue)
                .execute()
            return response.count ?? 0
        } catch { return 0 }
    }

    /// Conversations that have at least one unread message from an employee.
    /// The web expresses this as an inner join:
    /// `select("id, messages!inner(id)").eq("messages.sender_type","employee")
    ///  .eq("messages.is_read", false)` and counts the returned rows.
    static func countUnreadConversations(wholesalerID: UUID) async -> Int {
        struct Row: Decodable { let id: String }
        do {
            let rows: [Row] = try await db.from("conversations")
                .select("id, messages!inner(id)")
                .eq("wholesaler_id", value: wholesalerID.uuidString)
                .eq("messages.sender_type", value: "employee")
                .eq("messages.is_read", value: false)
                .execute()
                .value
            return rows.count
        } catch { return 0 }
    }

    private static func count(from table: String, column: String, value: String) async -> Int {
        do {
            let response = try await db.from(table)
                .select("*", head: true, count: .exact)
                .eq(column, value: value)
                .execute()
            return response.count ?? 0
        } catch { return 0 }
    }

    // MARK: - Catalogue

    /// Page size matches the web's catalogue (`limit` in
    /// `/api/catalogue/products`).
    static let cataloguePageSize = 20

    struct CataloguePage: Sendable {
        let products: [Product]
        let total: Int
        var hasMore: Bool { false }
    }

    /// Products for the signed-in wholesaler, newest first, optionally filtered
    /// to one category slug.
    static func fetchCatalogue(
        wholesalerID: UUID,
        category: String? = nil,
        page: Int = 0,
        pageSize: Int = cataloguePageSize
    ) async throws -> CataloguePage {
        var query = db.from("products")
            .select("*", count: .exact)
            .eq("wholesaler_id", value: wholesalerID.uuidString)

        if let category, !category.isEmpty {
            query = query.eq("category", value: category)
        }

        let from = page * pageSize
        let response = try await query
            .order("created_at", ascending: false)
            .range(from: from, to: from + pageSize - 1)
            .execute()

        let products = try JSONDecoder().decode([Product].self, from: response.data)
        return CataloguePage(products: products, total: response.count ?? products.count)
    }

    static func fetchProduct(id: String) async throws -> Product? {
        let rows: [Product] = try await db.from("products")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Mirrors `PATCH /api/products/{id}` — note the route renames `in_stock`
    /// to the `stock_available` column.
    static func updateProductFlags(
        id: String,
        inStock: Bool? = nil,
        isPublished: Bool? = nil
    ) async throws {
        struct Patch: Encodable {
            var stock_available: Bool?
            var is_published: Bool?
        }
        let patch = Patch(stock_available: inStock, is_published: isPublished)
        _ = try await db.from("products").update(patch).eq("id", value: id).execute()
    }

    /// Full edit, used by `/edit-product/[id]`.
    struct ProductEdit: Encodable {
        var title: String?
        var category: String?
        var style: String?
        var size: String?
        var metal_purity: String?
        var net_weight: Double?
        var gross_weight: Double?
        var stone_weight: Double?
        var stock_available: Bool?
        var make_to_order_days: Int?
        var is_published: Bool?
    }

    static func updateProduct(id: String, edit: ProductEdit) async throws {
        _ = try await db.from("products").update(edit).eq("id", value: id).execute()
    }

    static func deleteProduct(id: String) async throws {
        _ = try await db.from("products").delete().eq("id", value: id).execute()
    }

    // MARK: - Orders

    static func fetchOrders(wholesalerID: UUID) async throws -> [Order] {
        try await db.from("orders")
            .select()
            .eq("wholesaler_id", value: wholesalerID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// `PATCH /api/orders/{id}` — status transition, with the timestamp column
    /// the web's route stamps alongside it.
    static func updateOrderStatus(
        id: String,
        status: OrderStatus,
        rejectionReason: String? = nil
    ) async throws {
        var payload: [String: AnyJSON] = [
            "status": .string(status.rawValue),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date())),
        ]
        if let rejectionReason, !rejectionReason.isEmpty {
            payload["rejection_reason"] = .string(rejectionReason)
        }
        if let stamp = Self.timestampColumn(for: status) {
            payload[stamp] = .string(ISO8601DateFormatter().string(from: Date()))
        }
        _ = try await db.from("orders").update(payload).eq("id", value: id).execute()
    }

    private static func timestampColumn(for status: OrderStatus) -> String? {
        switch status {
        case .accepted: "accepted_at"
        case .rejected: "rejected_at"
        case .inProduction: "production_at"
        case .packed: "packed_at"
        case .dispatched: "dispatched_at"
        case .received: "received_at"
        case .completed: "completed_at"
        case .pending: nil
        }
    }

    // MARK: - Chat

    static func fetchConversations(wholesalerID: UUID) async throws -> [Conversation] {
        try await db.from("conversations")
            .select()
            .eq("wholesaler_id", value: wholesalerID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func fetchMessages(conversationID: String) async throws -> [ChatMessage] {
        try await db.from("messages")
            .select()
            .eq("conversation_id", value: conversationID)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    static func sendMessage(conversationID: String, content: String) async throws {
        struct NewMessage: Encodable {
            let conversation_id: String
            let content: String
            let sender_type: String
        }
        _ = try await db.from("messages")
            .insert(NewMessage(
                conversation_id: conversationID,
                content: content,
                sender_type: "wholesaler"
            ))
            .execute()
    }

    static func markMessagesRead(conversationID: String) async throws {
        struct Patch: Encodable { let is_read: Bool }
        _ = try await db.from("messages")
            .update(Patch(is_read: true))
            .eq("conversation_id", value: conversationID)
            .eq("sender_type", value: "employee")
            .execute()
    }

    // MARK: - AI pipeline

    struct PipelineError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// `GET {API}/api/upload-usage?wholesaler_id=`.
    /// The web swallows failures here and falls back to `used = 0`, unlimited.
    static func fetchUploadUsage(wholesalerID: UUID) async -> UploadUsage {
        var components = URLComponents(
            url: AppConfig.aiPipelineURL.appending(path: "/api/upload-usage"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "wholesaler_id", value: wholesalerID.uuidString)]
        guard let url = components?.url else { return .unknown }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData   // cache: "no-store"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .unknown
            }
            return try JSONDecoder().decode(UploadUsage.self, from: data)
        } catch {
            return .unknown
        }
    }

    /// `POST {API}/process` — multipart with the image plus the three fields
    /// the pipeline needs. Returns the created product id.
    static func processProduct(
        imageData: Data,
        filename: String,
        mimeType: String,
        title: String,
        jewelleryType: String,
        wholesalerID: UUID
    ) async throws -> ProcessResponse {
        var form = MultipartForm()
        form.addField(name: "title", value: title)
        form.addField(name: "jewellery_type", value: jewelleryType)
        form.addField(name: "wholesaler_id", value: wholesalerID.uuidString)
        form.addFile(name: "file", filename: filename, mimeType: mimeType, data: imageData)

        var request = URLRequest(url: AppConfig.aiPipelineURL.appending(path: "/process"))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalize()
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PipelineError(message: Copy.networkError)
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = detail?["detail"] as? String
                ?? detail?["message"] as? String
                ?? "Upload failed (\(http.statusCode)). Please try again."
            throw PipelineError(message: message)
        }
        return try JSONDecoder().decode(ProcessResponse.self, from: data)
    }

    /// `GET {API}/product/{id}` — used while polling for the generated renders.
    static func fetchPipelineProduct(id: String) async throws -> [String: Any] {
        let url = AppConfig.aiPipelineURL.appending(path: "/product/\(id)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PipelineError(message: "Couldn't read processing status.")
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Polling constants from the web (`POLL_INTERVAL_MS`, `POLL_TIMEOUT_MS`).
    static let pollInterval: Duration = .seconds(5)
    static let pollTimeout: Duration = .seconds(300)

    // MARK: - Storage

    /// Uploads one file and returns its public URL.
    ///
    /// The web routes this through `/api/onboard/submit`, which uses the
    /// service-role key. On device the user's own session is used instead —
    /// which requires the bucket to allow authenticated inserts under
    /// `auth.uid() = (storage.foldername(name))[1]`. If that policy is absent
    /// the throw surfaces verbatim so the cause is obvious.
    @discardableResult
    static func upload(
        bucket: String,
        path: String,
        data: Data,
        contentType: String
    ) async throws -> String {
        _ = try await db.storage.from(bucket).upload(
            path,
            data: data,
            options: FileOptions(contentType: contentType, upsert: true)
        )
        return try db.storage.from(bucket).getPublicURL(path: path).absoluteString
    }
}

/// Minimal multipart/form-data builder — the pipeline expects the same shape
/// the browser's `FormData` produces.
struct MultipartForm {
    let boundary = "Boundary-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func finalize() -> Data {
        var out = body
        out.append("--\(boundary)--\r\n")
        return out
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
