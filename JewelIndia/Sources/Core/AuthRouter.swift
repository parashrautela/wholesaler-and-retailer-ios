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
/// in.
///
/// One thing the web never had to decide: what to do when the lookup itself
/// fails. Its server either answers or 500s. Here a lookup that fails is
/// **not** the same as a row that is missing — treating them alike sent
/// people with a weak connection back into onboarding, or to the role
/// question, over an application they had already made. A failed lookup
/// routes to `.unreachable`, which keeps the session and retries.
enum AuthRouter {

    /// A row lookup with the three answers it can actually give.
    private enum Gate<Row> {
        case found(Row)
        case missing
        case unreachable
    }

    private static func gate<Row: Decodable & Sendable>(
        _ table: String,
        select columns: String,
        where column: String,
        equals value: String
    ) async -> Gate<Row> {
        do {
            let rows: [Row] = try await SupabaseManager.client
                .from(table)
                .select(columns)
                .eq(column, value: value)
                .limit(1)
                .execute()
                .value
            return rows.first.map { .found($0) } ?? .missing
        } catch {
            return .unreachable
        }
    }

    /// Resolves where a signed-in user belongs. Mirrors `signIn` steps 3–7.
    static func destination(for user: User) async -> AppDestination {
        let role: UserRole?
        if let metadataRole = metadataRole(of: user) {
            role = metadataRole
        } else {
            let profile: Gate<ProfileRole> = await gate(
                "profiles", select: "role", where: "id", equals: user.id.uuidString
            )
            switch profile {
            case .found(let row): role = row.role
            case .missing: role = nil
            case .unreachable: return .unreachable
            }
        }

        switch role {
        case .wholesaler:
            return await wholesalerDestination(userID: user.id)
        case .retailer:
            return await retailerDestination(userID: user.id)
        case .employee:
            return await employeeDestination(userID: user.id)
        case nil:
            // No door chosen yet.
            return .selectRole
        }
    }

    /// `role = user.user_metadata.role`, falling back to `profiles.role`.
    /// A failed profiles read counts as "no role" here; `destination(for:)`
    /// is the one that tells the two apart.
    static func resolveRole(for user: User) async -> UserRole? {
        if let role = metadataRole(of: user) { return role }
        let profile: Gate<ProfileRole> = await gate(
            "profiles", select: "role", where: "id", equals: user.id.uuidString
        )
        if case .found(let row) = profile { return row.role }
        return nil
    }

    private static func metadataRole(of user: User) -> UserRole? {
        user.userMetadata["role"]?.stringValue.flatMap(UserRole.init(rawValue:))
    }

    // MARK: - C4 · getWholesalerDestination

    static func wholesalerDestination(userID: UUID) async -> AppDestination {
        let result: Gate<WholesalerGate> = await gate(
            "wholesalers", select: "verification_status, has_visited_dashboard",
            where: "user_id", equals: userID.uuidString
        )
        switch result {
        case .unreachable:
            return .unreachable
        case .missing:
            return .wholesalerOnboarding
        case .found(let row):
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
    }

    // MARK: - C5 · getRetailerDestination

    static func retailerDestination(userID: UUID) async -> AppDestination {
        let result: Gate<RetailerGate> = await gate(
            "retailers", select: "verification_status",
            where: "user_id", equals: userID.uuidString
        )
        switch result {
        case .unreachable:
            return .unreachable
        case .missing:
            return .retailerOnboarding
        case .found(let row):
            switch row.verificationStatus {
            case .banned:
                try? await SupabaseManager.client.auth.signOut()
                return .entry(error: Copy.bannedError)
            case .verified:
                return ViewModeStore.mode(for: userID) == .retailer
                    ? .retailerDashboard
                    : .employeeDashboard
            default:
                return .retailerSubmitted
            }
        }
    }

    // MARK: - employees

    /// `signIn` step 6. Note the web's quirk: a **missing** employee row still
    /// routes to the dashboard, and only the proxy then bounces it out. Here
    /// that round trip is collapsed — a missing row lands on the staff sign-in
    /// with the message the web drops on the floor.
    static func employeeDestination(userID: UUID) async -> AppDestination {
        let result: Gate<EmployeeGate> = await gate(
            "employees", select: "status",
            where: "auth_user_id", equals: userID.uuidString
        )
        switch result {
        case .unreachable:
            return .unreachable
        case .missing:
            try? await SupabaseManager.client.auth.signOut()
            return .employeeLogin(error: Copy.employeeDeactivated)
        case .found(let row):
            if row.status != "active" {
                try? await SupabaseManager.client.auth.signOut()
                return .employeeLogin(error: Copy.employeeDeactivated)
            }
            return .employeeDashboard
        }
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

    /// A verified retailer now enters their own standalone marketplace by
    /// default. Employee mode remains an explicit switch and is persisted.
    static func mode(for userID: UUID) -> ViewMode {
        guard let raw = UserDefaults.standard.string(forKey: key(userID)),
              let mode = ViewMode(rawValue: raw)
        else { return .retailer }
        return mode
    }

    static func set(_ mode: ViewMode, for userID: UUID) {
        UserDefaults.standard.set(mode.rawValue, forKey: key(userID))
    }

    static func clear(for userID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(userID))
    }
}
