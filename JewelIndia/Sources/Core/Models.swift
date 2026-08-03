import Foundation

/// The three roles stored in `auth.users.raw_user_meta_data.role` and mirrored
/// into `public.profiles.role`.
enum UserRole: String, Codable, Sendable {
    case wholesaler
    case retailer
    case employee
}

/// `WHOLESALERS_TABLE.sql`:
/// `check (verification_status in ('pending','verified','rejected','on_hold','resubmission_required','banned'))`
///
/// The retailers table has no DDL in the web repo; its statuses are inferred
/// from `lib/supabase/middleware.js` and use the same domain.
enum VerificationStatus: String, Codable, Sendable {
    case pending
    case verified
    case rejected
    case onHold = "on_hold"
    case resubmissionRequired = "resubmission_required"
    case banned
}

/// `jewel_view_mode` — a 7-day cookie on the web, written only by
/// `POST /api/auth/toggle-view`. Absent is treated as `.employee` for a
/// verified retailer.
///
/// The web never clears it on sign-out, so it leaks between accounts on a
/// shared browser. On iOS it is stored per user id to close that hole.
enum ViewMode: String, Codable, Sendable {
    case employee
    case retailer
}

// MARK: - Row shapes

struct WholesalerGate: Decodable, Sendable {
    let verificationStatus: VerificationStatus?
    let hasVisitedDashboard: Bool?

    enum CodingKeys: String, CodingKey {
        case verificationStatus = "verification_status"
        case hasVisitedDashboard = "has_visited_dashboard"
    }
}

struct RetailerGate: Decodable, Sendable {
    let verificationStatus: VerificationStatus?

    enum CodingKeys: String, CodingKey {
        case verificationStatus = "verification_status"
    }
}

struct EmployeeGate: Decodable, Sendable {
    let status: String?
}

struct ProfileRole: Decodable, Sendable {
    let role: UserRole?
}

// MARK: - Destinations

/// Every terminal destination the web router can produce, from the
/// role × verification_status table in the auth spec (§5.4).
enum AppDestination: Equatable, Sendable {
    /// `/entry_page/signup` — the real front door.
    case entry(error: String?)
    /// `/entry_page/signin?identity=…`
    case signIn(identity: String)
    /// `/select-role` — signed in with no role.
    case selectRole
    /// `/onboard`
    case wholesalerOnboarding
    /// `/onboard/submitted`
    case wholesalerSubmitted
    /// `/dashboard/wholesaler`
    case wholesalerDashboard
    /// `/onboard-retailer`
    case retailerOnboarding
    /// `/onboard-retailer/submitted`
    case retailerSubmitted
    /// `/dashboard/retailer`
    case retailerDashboard
    /// `/dashboard/employee`
    case employeeDashboard
    /// `/employee-login?error=deactivated`
    case employeeLogin(error: String?)
}
