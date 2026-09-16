import Foundation
import Supabase

/// Data access for the employee view (`EmployeeShell` — `/dashboard/employee`
/// on the web).
///
/// The web reads all of this with the service-role key. The app has only the
/// user's own session, so each read below is one that session is allowed:
///
/// - `employees` by `auth_user_id` ("Employees can view self")
/// - the store's name, logo and theme through `employee_store_profile()`,
///   because an employee cannot read their store's `retailers` row and
///   opening that row would expose the retailer's KYC documents
/// - `retailer_designs`, `retailer_selections`, `conversations`, `orders` —
///   each has an employee read policy
///
/// **A retailer in employee view has no `employees` row here.** The web tries
/// to create a "virtual employee" for them, but `employees.password_plain`
/// is NOT NULL and that insert supplies none, so it fails there too. The app
/// does not invent a password to get round it: a retailer is identified by
/// their store instead (`EmployeeSession.Identity.store`).
enum EmployeeAPI {

    private static var db: SupabaseClient { SupabaseManager.client }

    struct EmployeeAPIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Session

    static func resolveSession(userID: UUID, isRetailer: Bool) async throws -> EmployeeSession {
        // PostgREST returns ids lowercase; the web's per-person seeds use them
        // exactly as stored, so they are never uppercased here.
        let uid = userID.uuidString.lowercased()

        struct EmployeeRow: Decodable {
            let id: String
            let retailer_id: String
            let status: String?
        }
        let rows: [EmployeeRow] = try await db.from("employees")
            .select("id, retailer_id, status")
            .eq("auth_user_id", value: uid)
            .limit(1)
            .execute()
            .value
        let employee = rows.first

        if !isRetailer {
            guard let employee, employee.status == "active" else {
                throw EmployeeAPIError(message: Copy.employeeDeactivated)
            }
        }

        let profile = try await storeProfile(uid: uid, isRetailer: isRetailer)
        guard let retailerID = profile?.retailer_id ?? employee?.retailer_id else {
            throw EmployeeAPIError(message: "No store is linked to this account.")
        }

        let storedTheme = isRetailer
            ? EmployeeTheme.normalized(UserDefaults.standard.string(forKey: EmployeeTheme.localKey))
            : nil

        return EmployeeSession(
            identity: employee.map { .employee(id: $0.id) } ?? .store,
            retailerID: retailerID.lowercased(),
            isRetailer: isRetailer,
            storeName: profile?.business_name?.trimmed.nilIfEmpty ?? "Your Store",
            storeLogoURL: profile?.business_logo_url?.trimmed.nilIfEmpty.flatMap(URL.init(string:)),
            theme: storedTheme ?? EmployeeTheme.normalized(profile?.selected_theme) ?? .indian
        )
    }

    private struct StoreProfile: Decodable {
        let retailer_id: String
        let business_name: String?
        let business_logo_url: String?
        let selected_theme: String?
    }

    /// `employee_store_profile()` when the database has it. Until that
    /// migration is applied, a retailer can still read their own row
    /// directly; a real employee gets the web's "Your Store" fallback.
    private static func storeProfile(uid: String, isRetailer: Bool) async throws -> StoreProfile? {
        if let rows: [StoreProfile] = try? await db.rpc("employee_store_profile").execute().value,
           let first = rows.first {
            return first
        }
        guard isRetailer else { return nil }

        struct OwnRow: Decodable {
            let id: String
            let business_name: String?
            let business_logo_url: String?
            let selected_theme: String?
        }
        let own: [OwnRow] = try await db.from("retailers")
            .select("id, business_name, business_logo_url, selected_theme")
            .eq("user_id", value: uid)
            .limit(1)
            .execute()
            .value
        return own.first.map {
            StoreProfile(
                retailer_id: $0.id,
                business_name: $0.business_name,
                business_logo_url: $0.business_logo_url,
                selected_theme: $0.selected_theme
            )
        }
    }

    // MARK: - Designs

    /// The store's live designs. Home asks without an order, like the web —
    /// its shuffle depends on the order rows arrive in; the Designs screen
    /// asks for newest first (`getEmployeeDesignsData`).
    static func fetchDesigns(retailerID: String, newestFirst: Bool = false) async throws -> [RetailerDesign] {
        let query = db.from("retailer_designs")
            .select(RetailerDesign.columns)
            .eq("retailer_id", value: retailerID)
            .eq("is_archived", value: false)
        if newestFirst {
            return try await query.order("created_at", ascending: false).execute().value
        }
        return try await query.execute().value
    }

    // MARK: - The store's shortlist

    /// The retailer's curated selection from the wholesaler marketplace,
    /// published products only, newest first.
    static func fetchSelectedProducts(retailerID: String) async throws -> [Product] {
        struct Selection: Decodable { let product_id: String }
        let selections: [Selection] = try await db.from("retailer_selections")
            .select("product_id")
            .eq("retailer_id", value: retailerID)
            .execute()
            .value
        let ids = selections.map(\.product_id)
        guard !ids.isEmpty else { return [] }

        return try await db.from("products")
            .select()
            .eq("is_published", value: true)
            .in("id", values: ids)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Unread dots

    /// A wholesaler has written something nobody on this side has read.
    static func hasUnreadQueries(_ session: EmployeeSession) async -> Bool {
        struct Row: Decodable { let id: String }
        var query = db.from("conversations")
            .select("id, messages!inner(id)")
            .eq("messages.sender_type", value: "wholesaler")
            .eq("messages.is_read", value: false)
        switch session.identity {
        case .employee(let id): query = query.eq("employee_id", value: id)
        case .store: query = query.eq("retailer_id", value: session.retailerID)
        }
        let rows: [Row] = (try? await query.limit(1).execute().value) ?? []
        return !rows.isEmpty
    }

    /// When an order last moved past "pending" — the Orders dot compares this
    /// with the last time the tab was opened.
    static func latestOrderUpdate(_ session: EmployeeSession) async -> Date? {
        struct Row: Decodable { let updated_at: String? }
        var query = db.from("orders")
            .select("updated_at")
            .neq("status", value: "pending")
        switch session.identity {
        case .employee(let id): query = query.eq("employee_id", value: id)
        case .store: query = query.eq("retailer_id", value: session.retailerID)
        }
        let rows: [Row] = (try? await query
            .order("updated_at", ascending: false)
            .limit(1)
            .execute()
            .value) ?? []
        return rows.first?.updated_at.flatMap(EmployeeDates.parse)
    }
}

// MARK: - Models

struct EmployeeSession: Sendable, Equatable {
    enum Identity: Sendable, Equatable {
        /// A real `employees` row (a staff login).
        case employee(id: String)
        /// A retailer looking at their own store as staff would.
        case store
    }

    let identity: Identity
    let retailerID: String
    let isRetailer: Bool
    let storeName: String
    let storeLogoURL: URL?
    let theme: EmployeeTheme

    /// What the web seeds its per-person choices with (`employees.id`). A
    /// retailer has no such row, so the store id stands in: stable, and
    /// the same on every device they use.
    var seedID: String {
        switch identity {
        case .employee(let id): id
        case .store: retailerID
        }
    }

    /// For the Orders dot's "last checked" marker, which the web keeps per
    /// browser; here it is kept per person.
    var storageKey: String { "employee_orders_last_checked.\(seedID)" }
}

/// The two themes the employee view actually applies. The retailer picker
/// also shows Utsav and Neelam, but they are locked, and the web treats any
/// other value as Indian (`normalizeThemeId`).
enum EmployeeTheme: String, Sendable {
    case indian, maharaja

    /// Where `StoreThemeView` records a claim on this device.
    static let localKey = "jewel_store_theme"

    static func normalized(_ raw: String?) -> EmployeeTheme? {
        raw.flatMap(EmployeeTheme.init(rawValue:))
    }

    /// Home hero background — landscape artwork, drawn to fill.
    var heroBackground: URL? {
        switch self {
        case .indian: CloudinaryArt.url("v1778318369/home_bg_ryyopk.svg", width: 1280)
        case .maharaja: CloudinaryArt.url("v1781085325/Maharaja_Theme_ymaqjt.svg", width: 1280)
        }
    }

    /// Behind a full-screen design or product.
    func detailBackground(landscape: Bool) -> URL? {
        switch (self, landscape) {
        case (.maharaja, _): CloudinaryArt.url("v1781085326/Maharaja_theme_infoPage_zslwde.svg", width: 1280)
        case (.indian, false): CloudinaryArt.url("v1781118947/theme1_vertical_sclwlj.svg", width: 1280)
        case (.indian, true): CloudinaryArt.url("v1781118947/theme1_horizontal_hog6yy.svg", width: 1470)
        }
    }
}

/// The web's artwork is SVG with photographs embedded, which iOS cannot
/// draw. Cloudinary converts on request; asking for WebP at display width
/// turns multi-megabyte files into tens of kilobytes.
enum CloudinaryArt {
    static func url(_ asset: String, width: Int) -> URL? {
        URL(string: "https://res.cloudinary.com/dcs0vuzwg/image/upload/f_webp,w_\(width),q_80/\(asset)")
    }

    static let viewModeCard = url("v1778318370/home_fg_gtjkeu.svg", width: 900)
    static let jewelLogo = URL(string: "https://res.cloudinary.com/dcs0vuzwg/image/upload/f_png,w_240/v1777013959/jewel_logo_rhgin9.svg")

    /// The tall image beside the designer collection on wide screens.
    static let collectionImages: [URL?] = [
        url("v1778318369/emp_static1_ywv9ro.svg", width: 800),
        url("v1778318368/emp_static2_vijtdd.svg", width: 800),
        url("v1778318368/emp_static3_xdapmt.svg", width: 800),
        url("v1778318368/emp_static4_q0ysjt.svg", width: 800),
    ]
}

/// A row of `retailer_designs` — something the store made itself.
struct RetailerDesign: Decodable, Identifiable, Hashable, Sendable {
    static let columns = "id, image_url, title, category, tags, is_archived, created_at, size, purity, net_weight, gross_weight, stone_weight, type, style_aesthetic, is_in_stock, production_time_days"

    let id: String
    let imageURL: String?
    let title: String?
    let category: String?
    let tags: [String]
    let createdAt: String?
    let size: String?
    let purity: String?
    let netWeight: Double?
    let grossWeight: Double?
    let stoneWeight: Double?
    let type: String?
    let styleAesthetic: String?
    let isInStock: Bool?
    let productionTimeDays: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, category, tags, size, purity, type
        case imageURL = "image_url"
        case createdAt = "created_at"
        case netWeight = "net_weight"
        case grossWeight = "gross_weight"
        case stoneWeight = "stone_weight"
        case styleAesthetic = "style_aesthetic"
        case isInStock = "is_in_stock"
        case productionTimeDays = "production_time_days"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        size = try c.decodeIfPresent(String.self, forKey: .size)
        purity = try c.decodeIfPresent(String.self, forKey: .purity)
        netWeight = Self.number(c, .netWeight)
        grossWeight = Self.number(c, .grossWeight)
        stoneWeight = Self.number(c, .stoneWeight)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        styleAesthetic = try c.decodeIfPresent(String.self, forKey: .styleAesthetic)
        isInStock = try? c.decodeIfPresent(Bool.self, forKey: .isInStock)
        productionTimeDays = try? c.decodeIfPresent(Int.self, forKey: .productionTimeDays)
    }

    init(id: String, imageURL: String?, title: String?, category: String? = nil, type: String? = nil,
         purity: String? = nil, netWeight: Double? = nil, grossWeight: Double? = nil,
         stoneWeight: Double? = nil, styleAesthetic: String? = nil, isInStock: Bool? = nil,
         productionTimeDays: Int? = nil) {
        self.id = id
        self.imageURL = imageURL
        self.title = title
        self.category = category
        self.tags = []
        self.createdAt = nil
        self.size = nil
        self.purity = purity
        self.netWeight = netWeight
        self.grossWeight = grossWeight
        self.stoneWeight = stoneWeight
        self.type = type
        self.styleAesthetic = styleAesthetic
        self.isInStock = isInStock
        self.productionTimeDays = productionTimeDays
    }

    /// Postgres `numeric` can arrive as a JSON number or a string.
    private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }

    var imageLink: URL? { imageURL?.trimmed.nilIfEmpty.flatMap(URL.init(string:)) }

    /// The card's label (`DesignerCollectionSection`).
    var cardTitle: String { title?.trimmed.nilIfEmpty ?? "Untitled design" }
}

enum EmployeeDates {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }
}
