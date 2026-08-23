import Foundation

// MARK: - Credit Wallet

public struct CreditWallet: Decodable, Sendable {
    public let ok: Bool
    public let available: Int
    public let lifetimeGranted: Int
    public let lifetimeSpent: Int
    public let lifetimeExpired: Int
    public let expiringSoon: Int
    public let nextExpiry: String?
    public let lowBalance: Bool
    public let lowBalanceThreshold: Int
    public let recoveryOwed: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case available
        case lifetimeGranted = "lifetime_granted"
        case lifetimeSpent = "lifetime_spent"
        case lifetimeExpired = "lifetime_expired"
        case expiringSoon = "expiring_soon"
        case nextExpiry = "next_expiry"
        case lowBalance = "low_balance"
        case lowBalanceThreshold = "low_balance_threshold"
        case recoveryOwed = "recovery_owed"
    }
}

// MARK: - Credit Price (Rate Card)

public struct CreditPrice: Decodable, Identifiable, Sendable {
    public var id: String { featureKey }
    public let featureKey: String
    public let credits: Int
    public let label: String
    public let description: String?
    public let sortOrder: Int?
    public let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case featureKey = "feature_key"
        case credits
        case label
        case description
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }
}

// MARK: - Credit Ledger Entry

public struct CreditLedgerEntry: Decodable, Identifiable, Sendable {
    public let id: String
    public let delta: Int
    public let kind: String
    public let featureKey: String?
    public let referenceType: String?
    public let referenceId: String?
    public let balanceAfter: Int
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case delta
        case kind
        case featureKey = "feature_key"
        case referenceType = "reference_type"
        case referenceId = "reference_id"
        case balanceAfter = "balance_after"
        case createdAt = "created_at"
    }

    /// Computed human-readable title based on transaction kind and feature key
    public var displayTitle: String {
        switch kind {
        case "debit":
            switch featureKey {
            case "chamak.generate":
                return "Chamak Fusion"
            case "chamak.generate_custom":
                return "Chamak Fusion (Custom Photos)"
            case "chamak.reroll":
                return "Try Again"
            case "product.upload":
                return "Product Upload"
            case "product.reprocess":
                return "Reprocess Product"
            default:
                return featureKey?.capitalized ?? "Credit Spend"
            }
        case "grant":
            if referenceType == "purchase" {
                return "Credits purchased"
            }
            return "Welcome gift"
        case "refund":
            return "Refunded — generation failed"
        case "expiry":
            return "Credits expired"
        case "adjustment":
            return "Adjustment"
        default:
            return kind.capitalized
        }
    }

    /// Date parsed from created_at
    public var date: Date? {
        ISO8601DateFormatter().date(from: createdAt)
            ?? FormatterCache.isoDate(from: createdAt)
    }
}

private enum FormatterCache {
    static let fractionalISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func isoDate(from string: String) -> Date? {
        fractionalISO.date(from: string)
    }
}
