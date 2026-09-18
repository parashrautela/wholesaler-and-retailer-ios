import Foundation
import Supabase

/// A store's staff, through the `staff-accounts` Edge Function (see its
/// README). Creating a login needs the service role, so every write goes
/// through the function; reading the list is a plain `employees` query that
/// row security limits to the caller's own store.
enum StaffAccountsAPI {

    private static var db: SupabaseClient { SupabaseManager.client }

    /// Where staff usernames live. It is only a username: nothing is ever
    /// sent there, and there is no "forgot password" — the store resets it.
    static let usernameDomain = "jewelindia.shop"

    /// Posted after anything that changes the list, so it reloads.
    static let changed = Notification.Name("jewel.staff.changed")

    struct StaffError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The address a staff member signs in with, from what they typed.
    static func address(forUsername typed: String) -> String {
        let text = typed.trimmed.lowercased()
        return text.contains("@") ? text : "\(text)@\(usernameDomain)"
    }

    // MARK: - Reading

    static let columns = "id, full_name, email, invite_email, designation, phone, status, join_method, is_system_generated, created_at"

    /// Everyone on the store's list except the owner's own hidden row.
    static func fetchStaff() async throws -> [StaffMember] {
        let rows: [StaffMember] = try await db.from("employees")
            .select(columns)
            .eq("is_system_generated", value: false)
            .order("created_at")
            .execute()
            .value
        return rows
    }

    // MARK: - Writing

    static func suggestUsername(fullName: String) async throws -> String {
        let reply = try await invoke(Request(action: "suggest", fullName: fullName))
        guard let username = reply.username else { throw StaffError(message: Copy.genericFailure) }
        return username
    }

    /// A password login. The password comes back once and is kept nowhere.
    static func createLogin(fullName: String, username: String, designation: String?, phone: String?)
        async throws -> (member: StaffMember, password: String) {
        let reply = try await invoke(Request(action: "create", fullName: fullName, username: username,
                                             designation: designation, phone: phone))
        guard let member = reply.employee, let password = reply.password else {
            throw StaffError(message: Copy.genericFailure)
        }
        NotificationCenter.default.post(name: changed, object: nil)
        return (member, password)
    }

    static func inviteGoogle(fullName: String, email: String, designation: String?, phone: String?)
        async throws -> StaffMember {
        let reply = try await invoke(Request(action: "invite_google", fullName: fullName, email: email,
                                             designation: designation, phone: phone))
        guard let member = reply.employee else { throw StaffError(message: Copy.genericFailure) }
        NotificationCenter.default.post(name: changed, object: nil)
        return member
    }

    static func resetPassword(_ id: String) async throws -> (member: StaffMember, password: String) {
        let reply = try await invoke(Request(action: "reset_password", employeeID: id))
        guard let member = reply.employee, let password = reply.password else {
            throw StaffError(message: Copy.genericFailure)
        }
        return (member, password)
    }

    static func setActive(_ id: String, _ active: Bool) async throws -> StaffMember {
        let reply = try await invoke(Request(action: "set_status", employeeID: id,
                                             status: active ? "active" : "inactive"))
        guard let member = reply.employee else { throw StaffError(message: Copy.genericFailure) }
        NotificationCenter.default.post(name: changed, object: nil)
        return member
    }

    static func remove(_ member: StaffMember) async throws {
        _ = try await invoke(Request(action: member.status == .invited ? "cancel_invite" : "remove",
                                     employeeID: member.id))
        NotificationCenter.default.post(name: changed, object: nil)
    }

    // MARK: - Transport

    private struct Request: Encodable {
        let action: String
        var fullName: String? = nil
        var username: String? = nil
        var email: String? = nil
        var designation: String? = nil
        var phone: String? = nil
        var employeeID: String? = nil
        var status: String? = nil

        enum CodingKeys: String, CodingKey {
            case action, username, email, designation, phone, status
            case fullName = "full_name"
            case employeeID = "employee_id"
        }
    }

    private struct Reply: Decodable {
        let ok: Bool
        let employee: StaffMember?
        let password: String?
        let username: String?
        let removed: String?
    }

    private struct Refusal: Decodable {
        let message: String?
    }

    private static func invoke(_ request: Request) async throws -> Reply {
        guard let session = try? await db.auth.session else {
            throw StaffError(message: "Please sign in again.")
        }
        do {
            return try await db.functions.invoke(
                "staff-accounts",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: request
                ),
                decoder: JSONDecoder()
            )
        } catch FunctionsError.httpError(_, let data) {
            let refusal = try? JSONDecoder().decode(Refusal.self, from: data)
            throw StaffError(message: refusal?.message ?? "Staff accounts aren't reachable right now. Please try again.")
        }
    }
}

/// One person on the store's staff list.
struct StaffMember: Decodable, Identifiable, Hashable, Sendable {
    enum Status: String, Decodable, Sendable {
        case active, inactive, invited
    }

    let id: String
    let fullName: String
    let email: String
    let inviteEmail: String?
    let designation: String?
    let phone: String?
    let status: Status
    let joinMethod: String
    let isSystemGenerated: Bool

    enum CodingKeys: String, CodingKey {
        case id, email, designation, phone, status
        case fullName = "full_name"
        case inviteEmail = "invite_email"
        case joinMethod = "join_method"
        case isSystemGenerated = "is_system_generated"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName) ?? "Staff"
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        inviteEmail = try c.decodeIfPresent(String.self, forKey: .inviteEmail)
        designation = try c.decodeIfPresent(String.self, forKey: .designation)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        status = (try? c.decodeIfPresent(Status.self, forKey: .status)) ?? .inactive
        joinMethod = try c.decodeIfPresent(String.self, forKey: .joinMethod) ?? "password"
        isSystemGenerated = try c.decodeIfPresent(Bool.self, forKey: .isSystemGenerated) ?? false
    }

    init(id: String, fullName: String, email: String, inviteEmail: String? = nil, designation: String? = nil,
         phone: String? = nil, status: Status, joinMethod: String, isSystemGenerated: Bool = false) {
        self.id = id
        self.fullName = fullName
        self.email = email
        self.inviteEmail = inviteEmail
        self.designation = designation
        self.phone = phone
        self.status = status
        self.joinMethod = joinMethod
        self.isSystemGenerated = isSystemGenerated
    }

    var signsInWithGoogle: Bool { joinMethod == "google" }

    /// `priya.pinejewels` for a password login; nil for Google staff.
    var username: String? {
        guard !signsInWithGoogle, let at = email.lastIndex(of: "@") else { return nil }
        return String(email[..<at])
    }

    /// What the store sees them signing in with.
    var signInLabel: String { signsInWithGoogle ? (inviteEmail ?? email) : email }
}
