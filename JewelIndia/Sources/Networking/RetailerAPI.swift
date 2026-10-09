import Foundation
import Supabase

/// Data access for the retailer surface, following the same shape as
/// `WholesalerAPI`. Deliberately minimal for now — only what
/// `RetailerOnboardSubmittedView` needs, mirroring `WholesalerAPI
/// .markDashboardVisited` exactly. The retailer dashboard/catalogue/employee
/// screens added in the feature-parity pass are UI-first and not yet wired to
/// live data; that is a separate, larger gap tracked outside this file.
enum RetailerAPI {

    private static var db: SupabaseClient { SupabaseManager.client }

    /// Same role as `WholesalerAPI.markDashboardVisited`: the router keeps a
    /// verified retailer on the submitted screen until this is set, which is
    /// otherwise only ever written by the dashboard itself.
    static func markDashboardVisited(userID: UUID) async {
        struct Patch: Encodable { let has_visited_dashboard: Bool }
        _ = try? await db.from("retailers")
            .update(Patch(has_visited_dashboard: true))
            .eq("user_id", value: userID.uuidString)
            .execute()
    }

    // MARK: - Store designs
    //
    // A store's own pieces (`retailer_designs`), which staff browse on their
    // Designs screen. Deliberately plain: the photo goes to storage and the
    // row goes to the table. Nothing here calls the AI pipeline — there is no
    // analysis, enhancement or upscaling, and so nothing to wait for or pay
    // for. The photo is only sized down on the device first.

    static func fetchStoreID(userID: UUID) async throws -> String {
        struct Row: Decodable { let id: String }
        let row: Row = try await db.from("retailers")
            .select("id")
            .eq("user_id", value: userID.uuidString)
            .single()
            .execute()
            .value
        return row.id
    }

    /// RLS returns only the caller's store.
    static func fetchDesigns() async throws -> [RetailerDesign] {
        try await db.from("retailer_designs")
            .select(RetailerDesign.columns)
            .eq("is_archived", value: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    struct NewDesign: Sendable {
        var title: String
        var type: String?
        var category: String?
        var style: String?
        var purity: String?
        var netWeight: Double?
        var inStock: Bool
        var productionDays: Int?
    }

    /// `photos` are JPEG data, already sized for upload; the first is the cover.
    static func addDesign(_ design: NewDesign, photos: [Data], userID: UUID) async throws {
        guard !photos.isEmpty else { return }
        let storeID = try await fetchStoreID(userID: userID)

        // Storage only accepts uploads into the caller's own folder.
        let folder = userID.uuidString.lowercased()
        var urls: [String] = []
        for photo in photos {
            let path = "\(folder)/\(UUID().uuidString.lowercased()).jpg"
            // Not `WholesalerAPI.upload`: that upserts, which needs an UPDATE
            // rule this bucket doesn't have. Every path here is new anyway.
            _ = try await db.storage.from("retailer-designs").upload(
                path, data: photo, options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
            urls.append(try db.storage.from("retailer-designs").getPublicURL(path: path).absoluteString)
        }

        struct Row: Encodable {
            let retailer_id: String
            let image_url: String
            let image_urls: [String]
            let title: String
            let type: String?
            let category: String?
            let style_aesthetic: String?
            let purity: String?
            let net_weight: Double?
            let is_in_stock: Bool
            let production_time_days: Int?
        }
        do {
            try await db.from("retailer_designs")
                .insert(Row(
                    retailer_id: storeID,
                    image_url: urls[0],
                    image_urls: urls,
                    title: design.title,
                    type: design.type,
                    // The web fills category from type when it is left empty.
                    category: design.category ?? design.type,
                    style_aesthetic: design.style,
                    purity: design.purity,
                    net_weight: design.netWeight,
                    is_in_stock: design.inStock,
                    production_time_days: design.inStock ? nil : design.productionDays
                ))
                .execute()
        } catch {
            // Don't leave photos behind for a design that was never saved.
            await removePhotos(urls)
            throw error
        }
    }

    static func deleteDesign(_ design: RetailerDesign) async throws {
        try await db.from("retailer_designs")
            .delete()
            .eq("id", value: design.id)
            .execute()
        if let url = design.imageURL { await removePhotos([url]) }
    }

    /// Best effort: a photo left in storage is untidy, never harmful.
    private static func removePhotos(_ urls: [String]) async {
        let marker = "/retailer-designs/"
        let paths = urls.compactMap { url -> String? in
            guard let range = url.range(of: marker) else { return nil }
            return String(url[range.upperBound...]).components(separatedBy: "?").first
        }
        guard !paths.isEmpty else { return }
        _ = try? await db.storage.from("retailer-designs").remove(paths: paths)
    }

    // MARK: - Store theme

    /// The theme this retailer has claimed, or nil if they never have.
    /// Same column the web writes (`RetailerThemeClient`), so a theme claimed
    /// on either side shows on both.
    static func fetchSelectedTheme(userID: UUID) async -> String? {
        struct Row: Decodable { let selected_theme: String? }
        let row: Row? = try? await db.from("retailers")
            .select("selected_theme")
            .eq("user_id", value: userID.uuidString)
            .single()
            .execute()
            .value
        return row?.selected_theme
    }

    @discardableResult
    static func setSelectedTheme(_ themeID: String, userID: UUID) async -> Bool {
        struct Patch: Encodable { let selected_theme: String }
        do {
            _ = try await db.from("retailers")
                .update(Patch(selected_theme: themeID))
                .eq("user_id", value: userID.uuidString)
                .execute()
            return true
        } catch {
            return false
        }
    }
}
