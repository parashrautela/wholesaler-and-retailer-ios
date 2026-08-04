import Foundation

/// Row shapes for the wholesaler surface. Column names match the SQL exactly
/// (`SUPABASE_SETUP.sql`, `WHOLESALERS_TABLE.sql`, `ORDERS_TABLE.sql`,
/// `CHAT_TABLES.sql`) so the same `select` strings the web uses work verbatim.

// MARK: - Wholesaler

struct Wholesaler: Decodable, Sendable {
    let id: String
    let userId: String?
    let email: String?
    let fullName: String?
    let businessName: String?
    let state: String?
    let city: String?
    let businessLogoURL: String?
    let verificationStatus: VerificationStatus?
    let hasVisitedDashboard: Bool?
    let lastCheckedOrdersAt: String?
    let rejectionReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case email
        case fullName = "full_name"
        case businessName = "business_name"
        case state, city
        case businessLogoURL = "business_logo_url"
        case verificationStatus = "verification_status"
        case hasVisitedDashboard = "has_visited_dashboard"
        case lastCheckedOrdersAt = "last_checked_orders_at"
        case rejectionReason = "rejection_reason"
    }

    /// `business_name || full_name || email.split("@")[0] || ""` — the exact
    /// fallback chain from `app/dashboard/wholesaler/page.jsx`.
    var displayName: String {
        if let n = businessName?.trimmed, !n.isEmpty { return n }
        if let n = fullName?.trimmed, !n.isEmpty { return n }
        if let e = email, let handle = e.split(separator: "@").first { return String(handle) }
        return ""
    }
}

// MARK: - Product

struct Product: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let wholesalerId: String?
    let wholesalerEmail: String?
    let title: String?
    let jewelleryType: String?
    let category: String?
    let style: String?
    let size: String?
    let stockAvailable: Bool?
    let makeToOrderDays: Int?
    let metalPurity: String?
    let netWeight: Double?
    let grossWeight: Double?
    let stoneWeight: Double?
    let rawImageURL: String?
    let processedImageURL: String?
    let isPublished: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case wholesalerId = "wholesaler_id"
        case wholesalerEmail = "wholesaler_email"
        case title
        case jewelleryType = "jewellery_type"
        case category, style, size
        case stockAvailable = "stock_available"
        case makeToOrderDays = "make_to_order_days"
        case metalPurity = "metal_purity"
        case netWeight = "net_weight"
        case grossWeight = "gross_weight"
        case stoneWeight = "stone_weight"
        case rawImageURL = "raw_image_url"
        case processedImageURL = "processed_image_url"
        case isPublished = "is_published"
        case createdAt = "created_at"
    }

    /// The catalogue shows the AI-processed render when it exists, else the
    /// original upload.
    var displayImageURL: URL? {
        let candidate = processedImageURL?.trimmed.nilIfEmpty ?? rawImageURL?.trimmed.nilIfEmpty
        return candidate.flatMap(URL.init(string:))
    }

    static func == (a: Product, b: Product) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Orders

enum OrderStatus: String, Codable, CaseIterable, Sendable {
    case pending, accepted, rejected
    case inProduction = "in_production"
    case packed, dispatched, received, completed
}

struct Order: Decodable, Identifiable, Sendable {
    let id: String
    let productId: String?
    let employeeId: String?
    let retailerId: String?
    let wholesalerId: String?
    let customizationNote: String?
    let rejectionReason: String?
    let status: OrderStatus?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case employeeId = "employee_id"
        case retailerId = "retailer_id"
        case wholesalerId = "wholesaler_id"
        case customizationNote = "customization_note"
        case rejectionReason = "rejection_reason"
        case status
        case createdAt = "created_at"
    }
}

// MARK: - Chat

struct Conversation: Decodable, Identifiable, Sendable {
    let id: String
    let wholesalerId: String?
    let retailerId: String?
    let employeeId: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case wholesalerId = "wholesaler_id"
        case retailerId = "retailer_id"
        case employeeId = "employee_id"
        case createdAt = "created_at"
    }
}

struct ChatMessage: Decodable, Identifiable, Sendable {
    let id: String
    let conversationId: String?
    let senderType: String?
    let content: String?
    let isRead: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderType = "sender_type"
        case content
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

// MARK: - AI pipeline

/// `GET {API}/api/upload-usage?wholesaler_id=` → `{used, limit, resets_at}`.
struct UploadUsage: Decodable, Sendable {
    let used: Int
    /// The web treats a missing/absent limit as `Infinity` and then renders the
    /// bare `used` count instead of `used/limit`.
    let limit: Int?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case used, limit
        case resetsAt = "resets_at"
    }

    static let unknown = UploadUsage(used: 0, limit: nil, resetsAt: nil)

    var isUnlimited: Bool { limit == nil }

    /// `"{used}/{limit}"`, or just `"{used}"` when the limit is unknown.
    var display: String {
        guard let limit else { return "\(used)" }
        return "\(used)/\(limit)"
    }

    var remaining: Int? {
        guard let limit else { return nil }
        return max(0, limit - used)
    }
}

/// `POST {API}/process` → `{message, product_id, raw_image_url}`.
struct ProcessResponse: Decodable, Sendable {
    let message: String?
    let productId: String?
    let rawImageURL: String?

    enum CodingKeys: String, CodingKey {
        case message
        case productId = "product_id"
        case rawImageURL = "raw_image_url"
    }
}

// MARK: - Catalogue categories

/// `lib/config/catalogueCategories.js` — same order, same slugs. The web's
/// remote/`public` images are bundled as `Cat*` assets.
struct CatalogueCategory: Identifiable, Hashable, Sendable {
    let name: String
    let slug: String
    let asset: String

    var id: String { slug }

    static let all: [CatalogueCategory] = [
        .init(name: "Necklace", slug: "necklace", asset: "CatNecklace"),
        .init(name: "Haram", slug: "haram", asset: "CatHaram"),
        .init(name: "Pendants", slug: "pendants", asset: "CatPendants"),
        .init(name: "Mangalsutras", slug: "mangalsutras", asset: "CatMangalsutras"),
        .init(name: "Chains", slug: "chains", asset: "CatChains"),
        .init(name: "Bangles", slug: "bangles", asset: "CatBangles"),
        .init(name: "Rings", slug: "rings", asset: "CatRings"),
        .init(name: "Earrings", slug: "earrings", asset: "CatEarrings"),
        .init(name: "Nosepins", slug: "nosepins", asset: "CatNosepins"),
    ]
}

// MARK: - Helpers

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
