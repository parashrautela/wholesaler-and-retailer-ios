import Foundation
import Supabase

/// Data access for the employee-view surface (`EmployeeShell` /
/// `/dashboard/employee` on the web).
///
/// The web's equivalent queries (`lib/cache/retailerEmployee.js`) go through
/// `supabaseAdmin`, the service-role client — but only for caching
/// convenience via `unstable_cache`, not because RLS requires it.
/// `SUPABASE_SETUP.sql` grants both the retailer and their employees
/// own-retailer read access under the ordinary session (e.g. "Employees can
/// view their retailer selections"), matching the pattern already used by
/// `WholesalerAPI`/`RetailerAPI`. The service-role key must never ship in
/// this binary — see `SupabaseManager`.
///
/// The web additionally auto-provisions a virtual `employees` row for a
/// retailer's first visit (`ensureVirtualEmployee`), which needs the service
/// role to insert. This app only reaches `EmployeeShell` via a retailer
/// toggling their own view mode, not a distinct employee login (`RetailerAPI`
/// already notes that's a separate, larger gap), so that provisioning step is
/// skipped entirely: the retailer's own `retailers` row and user id stand in
/// for the `employees` row and its id.
enum EmployeeAPI {

    private static var db: SupabaseClient { SupabaseManager.client }

    struct EmployeeAPIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct RetailerDesign: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let imageURL: String?
        let title: String?
        let category: String?

        enum CodingKeys: String, CodingKey {
            case id
            case imageURL = "image_url"
            case title
            case category
        }

        var displayImageURL: URL? {
            imageURL?.trimmed.nilIfEmpty.flatMap(URL.init(string:))
        }
    }

    struct HomeData: Sendable {
        let businessName: String
        let businessLogoURL: URL?
        let designs: [RetailerDesign]
        /// One of 4 deterministic hero-background variants, keyed by the
        /// same rule as the web's `assigned_bg_image` — the same person
        /// always gets the same value. The web renders this as one of 4
        /// Cloudinary SVG illustrations; `AsyncImage` can't decode a remote
        /// SVG, so the view maps this index to a plain tint/gradient instead
        /// of attempting to load the (unrenderable) image URL.
        let backgroundVariant: Int
    }

    /// 4 possible variants, matching the web's 4 static hero backgrounds
    /// (`app/dashboard/employee/page.jsx`) — keyed by the last hex digit of
    /// the seed id so the same person always gets the same one.
    private static let backgroundVariantCount = 4

    /// Mirrors `getEmployeeHomeData` plus the deterministic shuffle and
    /// background-image assignment in `app/dashboard/employee/page.jsx`.
    static func fetchHomeData(userID: UUID) async throws -> HomeData {
        struct RetailerRow: Decodable {
            let id: String
            let businessName: String?
            let businessLogoURL: String?

            enum CodingKeys: String, CodingKey {
                case id
                case businessName = "business_name"
                case businessLogoURL = "business_logo_url"
            }
        }

        let retailers: [RetailerRow] = try await db.from("retailers")
            .select("id, business_name, business_logo_url")
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let retailer = retailers.first else {
            throw EmployeeAPIError(message: "No retailer profile found for this account.")
        }

        let designs: [RetailerDesign] = try await db.from("retailer_designs")
            .select("id, image_url, title, category")
            .eq("retailer_id", value: retailer.id)
            .eq("is_archived", value: false)
            .execute()
            .value

        let seedString = userID.uuidString
        return HomeData(
            businessName: retailer.businessName?.trimmed.nilIfEmpty ?? "Your Store",
            businessLogoURL: retailer.businessLogoURL?.trimmed.nilIfEmpty.flatMap(URL.init(string:)),
            designs: shuffled(designs, seedString: seedString, keep: 6),
            backgroundVariant: backgroundIndex(for: seedString)
        )
    }

    /// Mirrors `getEmployeeSelectedProducts`: the retailer's curated
    /// selection from the wholesaler marketplace, published products only,
    /// newest first — there is no sort control on the web (`_spec/06-retailer
    /// -screens.md` §0), so none is added here either.
    static func fetchSelectedProducts(userID: UUID) async throws -> [Product] {
        struct RetailerRow: Decodable {
            let id: String
        }
        struct Selection: Decodable {
            let productId: String
            enum CodingKeys: String, CodingKey { case productId = "product_id" }
        }

        let retailers: [RetailerRow] = try await db.from("retailers")
            .select("id")
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let retailer = retailers.first else {
            throw EmployeeAPIError(message: "No retailer profile found for this account.")
        }

        let selections: [Selection] = try await db.from("retailer_selections")
            .select("product_id")
            .eq("retailer_id", value: retailer.id)
            .execute()
            .value
        let productIDs = selections.map(\.productId)
        guard !productIDs.isEmpty else { return [] }

        let products: [Product] = try await db.from("products")
            .select()
            .eq("is_published", value: true)
            .in("id", values: productIDs)
            .order("created_at", ascending: false)
            .execute()
            .value
        return products
    }

    // MARK: - Deterministic shuffle / assignment

    /// Same LCG PRNG as the web's `page.jsx`: a seed folded from the
    /// characters of `seedString`, then a Fisher-Yates shuffle using
    /// `seed = (1103515245 * seed + 12345) & 0x7fffffff` at each step, so the
    /// same user always sees their designs in the same order.
    private static func shuffled<T>(_ items: [T], seedString: String, keep: Int) -> [T] {
        var seed: Int32 = 0
        for scalar in seedString.utf16 {
            seed = seed &* 31 &+ Int32(scalar)
        }

        var result = items
        var i = result.count - 1
        while i > 0 {
            seed = (1_103_515_245 &* seed &+ 12345) & 0x7FFF_FFFF
            let j = Int(seed) % (i + 1)
            result.swapAt(i, j)
            i -= 1
        }
        return Array(result.prefix(keep))
    }

    private static func backgroundIndex(for seedString: String) -> Int {
        guard let lastChar = seedString.last,
              let value = lastChar.hexDigitValue
        else { return 0 }
        return value % backgroundVariantCount
    }
}
