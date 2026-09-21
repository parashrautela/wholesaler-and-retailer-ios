import Foundation
import Supabase

/// The one-time onboarding fee, served by the AI pipeline so its amount can
/// be changed in Railway without an app release.
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

    struct FeeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func status() async throws -> Status {
        try await call("GET", "")
    }

    static func createLink() async throws -> Link {
        try await call("POST", "/pay")
    }

    static func confirm(linkID: String) async throws -> Bool {
        struct Reply: Decodable { let paid: Bool }
        let reply: Reply = try await call("POST", "/confirm", body: ["link_id": linkID])
        return reply.paid
    }

    private static func call<T: Decodable>(_ method: String, _ path: String, body: [String: String]? = nil) async throws -> T {
        guard let session = try? await SupabaseManager.client.auth.session else {
            throw FeeError(message: "Your session isn't active on this device. Please sign in again.")
        }
        var request = URLRequest(url: AppConfig.aiPipelineURL.appending(path: "/api/onboarding/fee\(path)"))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw FeeError(message: detail?["detail"] as? String ?? "Payments aren't reachable right now. Please try again.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
