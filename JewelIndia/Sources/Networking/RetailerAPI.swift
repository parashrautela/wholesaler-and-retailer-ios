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
