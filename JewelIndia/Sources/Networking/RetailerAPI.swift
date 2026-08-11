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
}
