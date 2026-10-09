import Foundation
import Supabase

/// The one-time onboarding fee, served by the `credits-topup` function, which
/// already holds the Razorpay keys. The amount is the Supabase secret
/// ONBOARDING_FEE_INR, so it changes without an app release.
enum OnboardingFeeAPI {
    struct Status: Decodable, Sendable {
        let amountINR: Int
        let required: Bool
        /// False while the fee is set but can't be collected yet; then it
        /// must not stand in anyone's way.
        let payable: Bool
        let paid: Bool

        var mustPay: Bool { required && payable && !paid }

        enum CodingKeys: String, CodingKey {
            case required, payable, paid
            case amountINR = "amount_inr"
        }
    }

    struct Link: Decodable, Sendable {
        let paid: Bool?
        let linkID: String?
        let url: URL?

        enum CodingKeys: String, CodingKey {
            case paid, url
            case linkID = "link_id"
        }
    }

    private struct Refusal: Decodable { let message: String? }

    struct FeeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func status() async throws -> Status {
        try await call(["action": "onboarding_status"])
    }

    static func createLink() async throws -> Link {
        try await call(["action": "onboarding_pay"])
    }

    static func confirm(linkID: String) async throws -> Bool {
        struct Reply: Decodable { let paid: Bool }
        let reply: Reply = try await call(["action": "onboarding_confirm", "link_id": linkID])
        return reply.paid
    }

    private static func call<T: Decodable>(_ body: [String: String]) async throws -> T {
        // A fresh token, as the Top Up call does: `auth.session` refreshes one
        // that expired while the app sat idle.
        guard let session = try? await SupabaseManager.client.auth.session else {
            throw FeeError(message: "Your session isn't active on this device. Please sign in again.")
        }
        do {
            return try await SupabaseManager.client.functions.invoke(
                "credits-topup",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: body
                ),
                decoder: JSONDecoder()
            )
        } catch FunctionsError.httpError(_, let data) {
            let refusal = try? JSONDecoder().decode(Refusal.self, from: data)
            throw FeeError(message: refusal?.message ?? "Payments aren't reachable right now. Please try again.")
        }
    }
}
