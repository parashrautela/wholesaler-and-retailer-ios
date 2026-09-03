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
}
