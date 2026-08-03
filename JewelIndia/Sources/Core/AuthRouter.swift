import Foundation
import Supabase

/// The launch/login router — the native replacement for the Next proxy
/// (`lib/supabase/middleware.js`) plus the destination helpers in
/// `lib/actions/auth.js`.
///
/// The web has two slightly different implementations of the same table: the
/// proxy ignores `has_visited_dashboard`, while `getWholesalerDestination` in
/// `auth.js` consults it. A native client resolves its destination once, at
/// sign-in or launch, so it follows the **post-login (`auth.js`) variant** —
/// which is the one a web user actually experiences immediately after signing
/// in. The divergence is flagged in the Phase 1 notes.
enum AuthRouter {

    /// Resolves where a signed-in user belongs. Mirrors `signIn` steps 3–7.
    static func destination(for user: User) async -> AppDestination {
        let role = await resolveRole(for: user)

        switch role {
        case .wholesaler:
            return await wholesalerDestination(userID: user.id)
        case .retailer:
            return await retailerDestination(userID: user.id)
        case .employee:
            return await employeeDestination(userID: user.id)
        case nil:
            // `roleDestination(null)` → "/select-role"
            return .selectRole
        }
    }

    /// `role = user.user_metadata.role`, falling back to `profiles.role`.
    static func resolveRole(for user: User) async -> UserRole? {
        if let raw = user.userMetadata["role"]?.stringValue,
           let role = UserRole(rawValue: raw) {
            return role
        }
        let profile: ProfileRole? = try? await SupabaseManager.client
            .from("profiles")
            .select("role")
            .eq("id", value: user.id.uuidString)
            .single()
            .execute()
            .value
        return profile?.role
    }

    // MARK: - C4 · getWholesalerDestination

    static func wholesalerDestination(userID: UUID) async -> AppDestination {
        let row: WholesalerGate? = try? await SupabaseManager.client
            .from("wholesalers")
            .select("verification_status, has_visited_dashboard")
            .eq("user_id", value: userID.uuidString)
            .single()
            .execute()
            .value

        guard let row else { return .wholesalerOnboarding }

        switch row.verificationStatus {
        case .banned:
            try? await SupabaseManager.client.auth.signOut()
            return .entry(error: Copy.bannedError)
        case .verified:
            return row.hasVisitedDashboard == true
                ? .wholesalerDashboard
                : .wholesalerSubmitted
        default:
            return .wholesalerSubmitted
        }
    }

    // MARK: - C5 · getRetailerDestination

    static func retailerDestination(userID: UUID) async -> AppDestination {
        let row: RetailerGate? = try? await SupabaseManager.client
            .from("retailers")
            .select("verification_status")
            .eq("user_id", value: userID.uuidString)
            .single()
            .execute()
            .value

        guard let row else { return .retailerOnboarding }

        switch row.verificationStatus {
        case .banned:
            try? await SupabaseManager.client.auth.signOut()
            return .entry(error: Copy.bannedError)
        case .verified:
            // Absent view mode means employee mode, exactly as on the web.
            return ViewModeStore.mode(for: userID) == .retailer
                ? .retailerDashboard
                : .employeeDashboard
        default:
            return .retailerSubmitted
        }
    }

    // MARK: - employees

    /// `signIn` step 6. Note the web's quirk: a **missing** employee row still
    /// routes to the dashboard, and only the proxy then bounces it out. Here
    /// that round trip is collapsed — a missing row lands on the employee login
    /// with the message the web drops on the floor.
    static func employeeDestination(userID: UUID) async -> AppDestination {
        let row: EmployeeGate? = try? await SupabaseManager.client
            .from("employees")
            .select("status")
            .eq("auth_user_id", value: userID.uuidString)
            .single()
            .execute()
            .value

        guard let row else {
            try? await SupabaseManager.client.auth.signOut()
            return .employeeLogin(error: Copy.employeeDeactivated)
        }
        if row.status != "active" {
            try? await SupabaseManager.client.auth.signOut()
            return .employeeLogin(error: Copy.employeeDeactivated)
        }
        return .employeeDashboard
    }
}

/// `jewel_view_mode`, stored per user id.
///
/// On the web this is a 7-day httpOnly cookie that is never cleared on sign-out,
/// so it leaks between accounts on a shared browser. Keying it by user id keeps
/// the same semantics without the leak.
enum ViewModeStore {
    private static func key(_ userID: UUID) -> String {
        "jewel_view_mode.\(userID.uuidString)"
    }

    /// Absent ⇒ employee mode, matching the web's `!== "retailer"` test.
    static func mode(for userID: UUID) -> ViewMode {
        guard let raw = UserDefaults.standard.string(forKey: key(userID)),
              let mode = ViewMode(rawValue: raw)
        else { return .employee }
        return mode
    }

    static func set(_ mode: ViewMode, for userID: UUID) {
        UserDefaults.standard.set(mode.rawValue, forKey: key(userID))
    }

    static func clear(for userID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(userID))
    }
}
