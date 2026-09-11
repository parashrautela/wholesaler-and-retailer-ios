import Foundation
import Supabase

public enum CreditsAPI {
    private static var db: SupabaseClient { SupabaseManager.client }

    /// Calls `credits_wallet()` RPC to fetch the caller's wallet summary
    public static func fetchWallet() async throws -> CreditWallet {
        let wallet: CreditWallet = try await db
            .rpc("credits_wallet")
            .execute()
            .value
        return wallet
    }

    /// Fetches all active credit prices (the rate card) ordered by sort_order
    public static func fetchRateCard() async throws -> [CreditPrice] {
        let prices: [CreditPrice] = try await db
            .from("credit_prices")
            .select()
            .eq("is_active", value: true)
            .order("sort_order", ascending: true)
            .execute()
            .value
        return prices
    }

    /// Fetches transaction history from `credit_ledger`
    public static func fetchLedger(limit: Int = 50, before: Date? = nil) async throws -> [CreditLedgerEntry] {
        var filterQuery = db.from("credit_ledger")
            .select()

        if let before {
            let formatter = ISO8601DateFormatter()
            let dateString = formatter.string(from: before)
            filterQuery = filterQuery.lt("created_at", value: dateString)
        }

        let entries: [CreditLedgerEntry] = try await filterQuery
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return entries
    }

    // MARK: - Buying credits

    /// The packs on sale, priced by the server (`credits-topup`), so the app
    /// never works out money or credits itself.
    public static func fetchTopUpOptions() async throws -> TopUpOptions {
        try await invokeTopUp(["action": "options"])
    }

    /// A Razorpay payment page for one pack, made out to the signed-in
    /// wholesaler. The server decides the price and whose wallet it fills.
    public static func createTopUpLink(packKey: String) async throws -> TopUpLink {
        try await invokeTopUp(["action": "create", "pack_key": packKey])
    }

    /// The purchase `razorpay-webhook` recorded for this payment page, or nil
    /// until it has. The row and the credits land in one transaction, so a
    /// row means the credits are already in the wallet.
    public static func purchase(forLink linkID: String) async throws -> CreditPurchaseReceipt? {
        let rows: [CreditPurchaseReceipt] = try await db
            .from("credit_purchases")
            .select("id, credits")
            .eq("provider_ref", value: linkID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private static func invokeTopUp<T: Decodable>(_ body: [String: String]) async throws -> T {
        // A fresh token, as ChamakAPI does: `auth.session` refreshes one that
        // expired while the app sat idle.
        guard let session = try? await db.auth.session else {
            throw TopUpError(message: "Your session isn't active on this device. Please sign out and sign in again.")
        }
        do {
            return try await db.functions.invoke(
                "credits-topup",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: body
                ),
                decoder: JSONDecoder()
            )
        } catch FunctionsError.httpError(_, let data) {
            let refusal = try? JSONDecoder().decode(TopUpRefusal.self, from: data)
            throw TopUpError(message: refusal?.message ?? "Payments aren't reachable right now. Please try again.")
        }
    }

    private struct TopUpRefusal: Decodable {
        let message: String?
    }
}

/// What `credits-topup` says when it refuses; `message` is written for the user.
public struct TopUpError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

public struct TopUpOptions: Decodable, Sendable {
    public let packs: [TopUpPack]
}

public struct TopUpPack: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let label: String
    /// Excluding GST.
    public let priceINR: Double
    public let gstINR: Double
    /// What the wholesaler pays.
    public let totalINR: Double
    public let credits: Int

    public init(key: String, label: String, priceINR: Double, gstINR: Double, totalINR: Double, credits: Int) {
        self.key = key
        self.label = label
        self.priceINR = priceINR
        self.gstINR = gstINR
        self.totalINR = totalINR
        self.credits = credits
    }

    enum CodingKeys: String, CodingKey {
        case key, label, credits
        case priceINR = "price_inr"
        case gstINR = "gst_inr"
        case totalINR = "total_inr"
    }
}

public struct TopUpLink: Decodable, Equatable, Sendable {
    public let linkID: String
    public let url: URL
    public let credits: Int
    public let totalINR: Double

    enum CodingKeys: String, CodingKey {
        case url, credits
        case linkID = "link_id"
        case totalINR = "total_inr"
    }
}

public struct CreditPurchaseReceipt: Decodable, Sendable {
    public let id: UUID
    public let credits: Int
}
