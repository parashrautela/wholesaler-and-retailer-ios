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

    // MARK: - Entitlements

    /// The one-off unlocks this user owns (`theme.utsav`, …). RLS returns
    /// only the caller's rows; an expired one no longer counts.
    public static func fetchEntitlementKeys() async throws -> Set<String> {
        struct Row: Decodable {
            let entitlement_key: String
            let expires_at: Date?
        }
        let rows: [Row] = try await db
            .from("entitlements")
            .select("entitlement_key, expires_at")
            .execute()
            .value
        let now = Date()
        return Set(rows.filter { $0.expires_at.map { $0 > now } ?? true }.map(\.entitlement_key))
    }

    /// Buys a one-off unlock with the caller's own credits. The server prices
    /// it, charges the wallet and records the unlock in one transaction, and
    /// a retried call replays rather than charging twice.
    public static func purchaseEntitlement(key: String) async throws -> EntitlementPurchase {
        try await db
            .rpc("purchase_entitlement", params: ["p_key": key])
            .execute()
            .value
    }

    // MARK: - Buying credits

    /// The packs on sale, priced by the server (`credits-topup`), so the app
    /// never works out money or credits itself.
    public static func fetchTopUpOptions() async throws -> TopUpOptions {
        try await invokeTopUp(TopUpRequest(action: "options"))
    }

    /// A Razorpay payment page for one pack, made out to the signed-in
    /// wholesaler. The server decides the price and whose wallet it fills.
    public static func createTopUpLink(packKey: String) async throws -> TopUpLink {
        try await invokeTopUp(TopUpRequest(action: "create", packKey: packKey))
    }

    /// The same, for an amount the wholesaler typed (excluding GST). The
    /// server checks the amount and works out the credits.
    public static func createTopUpLink(amountINR: Int) async throws -> TopUpLink {
        try await invokeTopUp(TopUpRequest(action: "create", packKey: "custom", amountINR: amountINR))
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

    private struct TopUpRequest: Encodable {
        let action: String
        var packKey: String?
        var amountINR: Int?

        enum CodingKeys: String, CodingKey {
            case action
            case packKey = "pack_key"
            case amountINR = "amount_inr"
        }
    }

    private static func invokeTopUp<T: Decodable>(_ body: TopUpRequest) async throws -> T {
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

/// What `purchase_entitlement` answers. `ok` with `alreadyOwned` means
/// nothing was charged; `INSUFFICIENT_CREDITS` carries how far short.
public struct EntitlementPurchase: Decodable, Sendable {
    public let ok: Bool
    public let error: String?
    public let alreadyOwned: Bool
    public let charged: Int
    public let shortBy: Int?

    public var isInsufficientCredits: Bool { error == "INSUFFICIENT_CREDITS" }

    enum CodingKeys: String, CodingKey {
        case ok, error, charged
        case alreadyOwned = "already_owned"
        case shortBy = "short_by"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error)
        alreadyOwned = try c.decodeIfPresent(Bool.self, forKey: .alreadyOwned) ?? false
        charged = try c.decodeIfPresent(Int.self, forKey: .charged) ?? 0
        shortBy = try c.decodeIfPresent(Int.self, forKey: .shortBy)
    }
}

/// What `credits-topup` says when it refuses; `message` is written for the user.
public struct TopUpError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

public struct TopUpOptions: Decodable, Sendable {
    public let packs: [TopUpPack]
    /// Credits per ₹1 excluding GST, and the GST added on top — used to
    /// quote a typed amount before the server prices it for real.
    public let creditsPerRupee: Double
    public let gstPercent: Int
    /// The range a wholesaler may type, or nil if the server doesn't allow one.
    public let custom: CustomAmountRange?

    public struct CustomAmountRange: Decodable, Sendable {
        public let minINR: Int
        public let maxINR: Int

        enum CodingKeys: String, CodingKey {
            case minINR = "min_inr"
            case maxINR = "max_inr"
        }
    }

    enum CodingKeys: String, CodingKey {
        case packs, custom
        case creditsPerRupee = "credits_per_rupee"
        case gstPercent = "gst_percent"
    }

    public init(packs: [TopUpPack], creditsPerRupee: Double = 10, gstPercent: Int = 18, custom: CustomAmountRange? = nil) {
        self.packs = packs
        self.creditsPerRupee = creditsPerRupee
        self.gstPercent = gstPercent
        self.custom = custom
    }

    /// Tolerant of an older server that doesn't send every field yet.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        packs = try c.decodeIfPresent([TopUpPack].self, forKey: .packs) ?? []
        creditsPerRupee = try c.decodeIfPresent(Double.self, forKey: .creditsPerRupee) ?? 10
        gstPercent = try c.decodeIfPresent(Int.self, forKey: .gstPercent) ?? 18
        custom = try c.decodeIfPresent(CustomAmountRange.self, forKey: .custom)
    }
}

/// What a typed amount costs and buys. Mirrors `credits-topup/lib.ts`
/// exactly — integer paise, GST added then split back out, credits rounded
/// down — so the screen never promises a number the wallet won't receive.
public enum TopUpQuote {
    public static func of(amountExGST: Int, gstPercent: Int, creditsPerRupee: Double) -> (gstINR: Double, totalINR: Double, credits: Int) {
        let totalPaise = ((amountExGST * 100 * (100 + gstPercent)) / 100)
        let taxablePaise = Int((Double(totalPaise * 100) / Double(100 + gstPercent)).rounded())
        let credits = Int((Double(taxablePaise) * creditsPerRupee / 100).rounded(.down))
        return (Double(totalPaise - taxablePaise) / 100, Double(totalPaise) / 100, credits)
    }
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
