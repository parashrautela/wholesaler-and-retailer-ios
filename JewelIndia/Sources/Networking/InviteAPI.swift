import Foundation
import Supabase

/// A wholesaler's invitation, as the retailer door uses it.
///
/// Retailers join with a code a wholesaler shared. The code is checked before
/// an account exists (so `validate_referral_code` runs with the anon key),
/// spent when the application is written (`retailers` insert, in the
/// database), and can be attached afterwards by a retailer who applied
/// before codes were required (`attach_referral_code`).
enum InviteAPI {

    private static var db: SupabaseClient { SupabaseManager.client }

    /// What the database says about a code, in the retailer's words.
    enum Check: Equatable, Sendable {
        case valid(code: String, wholesaler: String?)
        case invalid(reason: String, message: String)

        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
    }

    private struct Answer: Decodable {
        let valid: Bool
        let reason: String?
        let code: String?
        let wholesaler_name: String?
    }

    static func validate(_ raw: String) async throws -> Check {
        let code = raw.trimmed.uppercased()
        guard !code.isEmpty else {
            return .invalid(reason: "no_code", message: Copy.inviteCodeEmpty)
        }
        let answer: Answer = try await db
            .rpc("validate_referral_code", params: ["p_code": code])
            .execute()
            .value
        if answer.valid {
            return .valid(code: answer.code ?? code, wholesaler: answer.wholesaler_name?.trimmed.nilIfEmpty)
        }
        return .invalid(reason: answer.reason ?? "invalid", message: Copy.inviteCodeReason(answer.reason))
    }

    /// A pending retailer adds the code they were given after the fact.
    static func attach(_ raw: String) async throws {
        _ = try await db
            .rpc("attach_referral_code", params: ["p_code": raw.trimmed.uppercased()])
            .execute()
    }
}

/// The database refuses some things by name (`raise exception 'INVITE_CODE_USED'`).
/// This turns those names into sentences a person can act on.
enum DBRefusal {
    static func code(in error: Error) -> String? {
        let text = (error as? PostgrestError)?.message ?? error.localizedDescription
        let known = [
            "INVITE_CODE_REQUIRED", "INVITE_CODE_NOT_FOUND", "INVITE_CODE_EXPIRED", "INVITE_CODE_USED",
            "INVITE_CODE_INACTIVE", "RETAILER_ALREADY_ATTRIBUTED", "RETAILER_ALREADY_VERIFIED",
            "RETAILER_HAS_NO_INVITER", "ROLE_ALREADY_SET", "ROLE_NOT_ALLOWED", "NOT_SIGNED_IN",
            "NOT_INVITED", "GOOGLE_SIGN_IN_REQUIRED", "ACCOUNT_HAS_ANOTHER_ROLE",
        ]
        return known.first { text.contains($0) }
    }

    static func message(for error: Error) -> String {
        switch code(in: error) {
        case "INVITE_CODE_REQUIRED": Copy.inviteCodeEmpty
        case "INVITE_CODE_NOT_FOUND": Copy.inviteCodeReason("not_found")
        case "INVITE_CODE_EXPIRED": Copy.inviteCodeReason("expired")
        case "INVITE_CODE_USED": Copy.inviteCodeReason("used")
        case "INVITE_CODE_INACTIVE": Copy.inviteCodeReason("inactive")
        case "RETAILER_ALREADY_ATTRIBUTED": "Your store is already linked to the wholesaler who invited you."
        case "RETAILER_ALREADY_VERIFIED": "Your store is already verified — no code needed."
        case "ROLE_ALREADY_SET": Copy.roleAlreadySet
        case "ROLE_NOT_ALLOWED": Copy.roleNotAllowed
        case "NOT_SIGNED_IN": "Please sign in again."
        case "NOT_INVITED": Copy.staffNotInvited
        case "GOOGLE_SIGN_IN_REQUIRED": Copy.staffGoogleRequired
        case "ACCOUNT_HAS_ANOTHER_ROLE": Copy.staffAccountHasAnotherRole
        default: error.localizedDescription
        }
    }
}
