import Foundation
import Supabase

/// Order status changes, for every role.
///
/// `orders` has SELECT policies only — a direct UPDATE matches no rows and
/// reports success, which is how Accept once "did nothing". Every change goes
/// through `order_set_status`, which works out which side the caller is on
/// from the tables and allows only that side's next steps.
enum OrdersAPI {
    private static var db: SupabaseClient { SupabaseManager.client }

    struct ActionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func setStatus(orderID: String, status: OrderStatus, reason: String? = nil) async throws {
        struct Params: Encodable {
            let p_order: String
            let p_status: String
            let p_reason: String?
        }
        struct Reply: Decodable {
            let ok: Bool
            let error: String?
            let from: String?
        }
        let reply: Reply = try await db
            .rpc("order_set_status", params: Params(p_order: orderID, p_status: status.rawValue, p_reason: reason))
            .execute()
            .value
        guard !reply.ok else { return }

        switch reply.error {
        case "INVALID_TRANSITION":
            // The other side moved it first, or this list is stale.
            throw ActionError(message: "This order has already moved on. Pull down to refresh.")
        case "NOT_FOUND":
            throw ActionError(message: "This order is no longer available.")
        case "REASON_REQUIRED":
            throw ActionError(message: "Choose a reason for rejecting this order.")
        default:
            throw ActionError(message: "Couldn't update the order. Please try again.")
        }
    }

    /// The wholesaler's orders, with the design and the store on each. The
    /// store's name comes from the server: a wholesaler can't read
    /// `retailers` directly.
    static func fetchWholesalerOrders() async throws -> [WholesalerOrder] {
        try await db.rpc("wholesaler_orders").execute().value
    }

    /// The signed-in staff member's own orders, with the design on each.
    /// RLS (`employees_own_orders`) scopes the read; the app sends no ids.
    static func fetchStaffOrders() async throws -> [StaffOrder] {
        try await db.from("orders")
            .select("id, status, customization_note, rejection_reason, created_at, product:product_id(title, processed_image_url, image_url, raw_image_url)")
            .order("created_at", ascending: false)
            .execute()
            .value
    }
}

struct StaffOrder: Decodable, Identifiable, Sendable {
    let id: String
    let status: OrderStatus?
    let note: String?
    let rejectionReason: String?
    let createdAt: String?
    let product: DesignSummary?

    struct DesignSummary: Decodable, Sendable {
        let title: String?
        let processedImageURL: String?
        let imageURL: String?
        let rawImageURL: String?

        var image: URL? {
            [processedImageURL, imageURL, rawImageURL]
                .compactMap { $0?.trimmed.nilIfEmpty }
                .first
                .flatMap(URL.init(string:))
        }

        enum CodingKeys: String, CodingKey {
            case title
            case processedImageURL = "processed_image_url"
            case imageURL = "image_url"
            case rawImageURL = "raw_image_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, status, product
        case note = "customization_note"
        case rejectionReason = "rejection_reason"
        case createdAt = "created_at"
    }
}

struct WholesalerOrder: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let status: OrderStatus?
    let note: String?
    let rejectionReason: String?
    let createdAt: String?
    let acceptedAt: String?
    let rejectedAt: String?
    let productionAt: String?
    let packedAt: String?
    let dispatchedAt: String?
    let receivedAt: String?
    let completedAt: String?
    let productTitle: String?
    let productImage: String?
    let productType: String?
    let storeName: String?
    let storeCity: String?
    let placedBy: String?
    let placedByStaff: Bool

    var shortID: String { String(id.prefix(8)) }
    var imageURL: URL? { productImage?.trimmed.nilIfEmpty.flatMap(URL.init(string:)) }
    var designTitle: String {
        productTitle?.trimmed.nilIfEmpty ?? productType?.capitalized ?? "Jewellery order"
    }
    /// "Store name · City" for the card.
    var storeLine: String {
        [storeName?.trimmed.nilIfEmpty ?? "Retail store", storeCity].compactMap { $0 }.joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case note = "customization_note"
        case rejectionReason = "rejection_reason"
        case createdAt = "created_at"
        case acceptedAt = "accepted_at"
        case rejectedAt = "rejected_at"
        case productionAt = "production_at"
        case packedAt = "packed_at"
        case dispatchedAt = "dispatched_at"
        case receivedAt = "received_at"
        case completedAt = "completed_at"
        case productTitle = "product_title"
        case productImage = "product_image"
        case productType = "product_type"
        case storeName = "store_name"
        case storeCity = "store_city"
        case placedBy = "placed_by"
        case placedByStaff = "placed_by_staff"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try? c.decodeIfPresent(OrderStatus.self, forKey: .status)
        note = try c.decodeIfPresent(String.self, forKey: .note)?.trimmed.nilIfEmpty
        rejectionReason = try c.decodeIfPresent(String.self, forKey: .rejectionReason)?.trimmed.nilIfEmpty
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        acceptedAt = try c.decodeIfPresent(String.self, forKey: .acceptedAt)
        rejectedAt = try c.decodeIfPresent(String.self, forKey: .rejectedAt)
        productionAt = try c.decodeIfPresent(String.self, forKey: .productionAt)
        packedAt = try c.decodeIfPresent(String.self, forKey: .packedAt)
        dispatchedAt = try c.decodeIfPresent(String.self, forKey: .dispatchedAt)
        receivedAt = try c.decodeIfPresent(String.self, forKey: .receivedAt)
        completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
        productTitle = try c.decodeIfPresent(String.self, forKey: .productTitle)
        productImage = try c.decodeIfPresent(String.self, forKey: .productImage)
        productType = try c.decodeIfPresent(String.self, forKey: .productType)
        storeName = try c.decodeIfPresent(String.self, forKey: .storeName)
        storeCity = try c.decodeIfPresent(String.self, forKey: .storeCity)
        placedBy = try c.decodeIfPresent(String.self, forKey: .placedBy)
        placedByStaff = try c.decodeIfPresent(Bool.self, forKey: .placedByStaff) ?? false
    }

    #if DEBUG
    /// Peeks only.
    init(id: String, status: OrderStatus, note: String?, storeName: String, storeCity: String?,
         placedBy: String?, productTitle: String, productImage: String?, createdAt: String,
         acceptedAt: String? = nil, packedAt: String? = nil, dispatchedAt: String? = nil,
         rejectedAt: String? = nil, rejectionReason: String? = nil) {
        self.id = id; self.status = status; self.note = note; self.rejectionReason = rejectionReason
        self.createdAt = createdAt; self.acceptedAt = acceptedAt; self.rejectedAt = rejectedAt
        self.productionAt = nil; self.packedAt = packedAt; self.dispatchedAt = dispatchedAt
        self.receivedAt = nil; self.completedAt = nil
        self.productTitle = productTitle; self.productImage = productImage; self.productType = "necklace"
        self.storeName = storeName; self.storeCity = storeCity; self.placedBy = placedBy; self.placedByStaff = false
    }
    #endif
}

/// Chat between a store and a wholesaler, about one design.
///
/// The same rules as orders: the tables are read-only to the app, and every
/// write goes through a function that decides which side the caller is on.
/// A thread is opened from the store side only.
enum ChatAPI {
    private static var db: SupabaseClient { SupabaseManager.client }

    struct ChatError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Reply: Decodable {
        let ok: Bool
        let error: String?
        let conversationID: String?

        enum CodingKeys: String, CodingKey {
            case ok, error
            case conversationID = "conversation_id"
        }
    }

    /// The caller's threads, newest activity first. The server decides what
    /// each side may see: a wholesaler gets the store's name, a store gets
    /// the design only — suppliers stay private until an order.
    static func fetchThreads() async throws -> [ChatThread] {
        try await db.rpc("chat_threads").execute().value
    }

    /// Opens — or finds — this store's thread about a design.
    static func open(productID: String) async throws -> String {
        let reply: Reply = try await db
            .rpc("chat_open", params: ["p_product": productID])
            .execute()
            .value
        guard reply.ok, let id = reply.conversationID else {
            throw ChatError(message: reply.error == "NO_STORE"
                ? "Only a store can start a conversation about a design."
                : "Couldn't start the conversation. Please try again.")
        }
        return id
    }

    static func fetchMessages(conversationID: String) async throws -> [ChatMessage] {
        try await db.from("messages")
            .select()
            .eq("conversation_id", value: conversationID)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    static func send(conversationID: String, content: String) async throws {
        let reply: Reply = try await db
            .rpc("chat_send", params: ["p_conversation": conversationID, "p_content": content])
            .execute()
            .value
        guard reply.ok else {
            throw ChatError(message: "Your message didn't send. Please try again.")
        }
    }

    /// Marks the other side's messages read. Best effort — a failure here
    /// must never get in the way of reading.
    static func markRead(conversationID: String) async {
        _ = try? await db
            .rpc("chat_mark_read", params: ["p_conversation": conversationID])
            .execute()
    }
}

struct ChatThread: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    /// Which side the caller is on: `wholesaler` or `employee` (the store).
    let side: String
    let productID: String?
    let productTitle: String?
    let productImage: String?
    /// Wholesaler side only.
    let storeName: String?
    let askedBy: String?
    let lastMessage: String?
    let lastFrom: String?
    let lastAt: String?
    let unread: Int

    var imageURL: URL? { productImage?.trimmed.nilIfEmpty.flatMap(URL.init(string:)) }

    /// The name on the row and the thread's title.
    var title: String {
        if side == "wholesaler", let storeName = storeName?.trimmed.nilIfEmpty { return storeName }
        return productTitle?.trimmed.nilIfEmpty ?? "Design enquiry"
    }

    /// The line under it: for a wholesaler, which design and who asked.
    var subtitle: String? {
        guard side == "wholesaler" else { return nil }
        return [productTitle?.trimmed.nilIfEmpty, askedBy?.trimmed.nilIfEmpty.map { "asked by \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, side, unread
        case productID = "product_id"
        case productTitle = "product_title"
        case productImage = "product_image"
        case storeName = "store_name"
        case askedBy = "asked_by"
        case lastMessage = "last_message"
        case lastFrom = "last_from"
        case lastAt = "last_at"
    }

    init(id: String, side: String, productID: String? = nil, productTitle: String?, productImage: String? = nil,
         storeName: String? = nil, askedBy: String? = nil, lastMessage: String? = nil,
         lastFrom: String? = nil, lastAt: String? = nil, unread: Int = 0) {
        self.id = id
        self.side = side
        self.productID = productID
        self.productTitle = productTitle
        self.productImage = productImage
        self.storeName = storeName
        self.askedBy = askedBy
        self.lastMessage = lastMessage
        self.lastFrom = lastFrom
        self.lastAt = lastAt
        self.unread = unread
    }
}
