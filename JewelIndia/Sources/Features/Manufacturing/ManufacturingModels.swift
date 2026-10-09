import Foundation

// MARK: - Enums

public enum MakingBudgetMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case perGram = "per_gram"
    case fixedTotal = "fixed_total"
    case percentage = "percentage"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .perGram: "Per Gram (₹/g)"
        case .fixedTotal: "Fixed Total (₹)"
        case .percentage: "Percentage (%)"
        }
    }

    public var unitLabel: String {
        switch self {
        case .perGram: "₹/g"
        case .fixedTotal: "₹"
        case .percentage: "%"
        }
    }
}

public enum ManufacturingRequestState: String, Codable, CaseIterable, Sendable {
    case routing
    case collecting
    case reviewing
    case assigned
    case exhausted
    case cancelled

    public var title: String {
        switch self {
        case .collecting: "Collecting Quotes"
        case .reviewing: "Compare Quotes"
        case .routing: "Routing to Wholesalers"
        case .assigned: "Supplier Selected"
        case .exhausted: "No Suppliers Available"
        case .cancelled: "Cancelled"
        }
    }
}

public enum ManufacturingOfferStatus: String, Codable, CaseIterable, Sendable {
    case active
    case open
    case quoted
    case notSelected = "not_selected"
    case accepted
    case declined
    case expired
    case cancelled
    case skipped

    public var title: String {
        switch self {
        case .open: "Open for Quotes"
        case .quoted: "Quote Submitted"
        case .notSelected: "Another Quote Selected"
        case .active: "Active"
        case .accepted: "Accepted"
        case .declined: "Declined"
        case .expired: "Expired"
        case .cancelled: "Cancelled"
        case .skipped: "Skipped"
        }
    }
}

// MARK: - Models

public struct ManufacturingRequest: Codable, Identifiable, Hashable, Equatable, Sendable {
    public let id: UUID
    public let category: String
    public let minWeightGrams: Double
    public let maxWeightGrams: Double
    public let material: String
    public let purity: String
    public let gemstonePreference: String
    public let quantity: Int
    public let makingBudgetMode: String
    public let makingBudgetAmount: Double
    public let currency: String
    public let metalRateSnapshot: Double?
    public let metalRateBasis: String?
    public let deliveryNeededDate: String
    public let notes: String?
    public let state: String
    public let activeOfferId: UUID?
    public let assignedWholesalerId: UUID?
    public var assignedWholesalerName: String?
    public var imageUrl: String?
    public var quote: ManufacturingQuote?
    public var quotes: [ManufacturingQuote]?
    public let broadcastMode: String?
    public let quotationDeadline: String?
    public var assignedWholesaler: WholesalerBusinessSummary?
    public var activeOffer: ManufacturingOfferSummary?
    public let createdAt: String?
    public let updatedAt: String?
    public let assignedAt: String?
    public let cancelledAt: String?

    enum CodingKeys: String, CodingKey {
        case id, category, material, purity, quantity, currency, notes, state
        case minWeightGrams = "min_weight_grams"
        case maxWeightGrams = "max_weight_grams"
        case gemstonePreference = "gemstone_preference"
        case makingBudgetMode = "making_budget_mode"
        case makingBudgetAmount = "making_budget_amount"
        case metalRateSnapshot = "metal_rate_snapshot"
        case metalRateBasis = "metal_rate_basis"
        case deliveryNeededDate = "delivery_needed_date"
        case activeOfferId = "active_offer_id"
        case assignedWholesalerId = "assigned_wholesaler_id"
        case assignedWholesalerName = "assigned_wholesaler_name"
        case imageUrl = "image_url"
        case quote, quotes
        case broadcastMode = "broadcast_mode"
        case quotationDeadline = "quotation_deadline"
        case assignedWholesaler = "assigned_wholesaler"
        case activeOffer = "active_offer"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case assignedAt = "assigned_at"
        case cancelledAt = "cancelled_at"
    }

    public var parsedState: ManufacturingRequestState {
        ManufacturingRequestState(rawValue: state) ?? .routing
    }

    public var parsedBudgetMode: MakingBudgetMode {
        MakingBudgetMode(rawValue: makingBudgetMode) ?? .perGram
    }

    public var formattedWeightRange: String {
        if abs(minWeightGrams - maxWeightGrams) < 0.001 {
            return String(format: "%.1f g", minWeightGrams)
        }
        return String(format: "%.1f - %.1f g", minWeightGrams, maxWeightGrams)
    }

    public var formattedBudget: String {
        switch parsedBudgetMode {
        case .perGram:
            return String(format: "₹%.0f/g", makingBudgetAmount)
        case .fixedTotal:
            return String(format: "₹%.0f total", makingBudgetAmount)
        case .percentage:
            return String(format: "%.1f%%", makingBudgetAmount)
        }
    }
}

public struct WholesalerBusinessSummary: Codable, Hashable, Equatable, Sendable {
    public let id: UUID
    public let businessName: String?
    public let city: String?
    public let state: String?

    enum CodingKeys: String, CodingKey {
        case id
        case businessName = "business_name"
        case city, state
    }
}

public struct ManufacturingOfferSummary: Codable, Hashable, Equatable, Sendable {
    public let id: UUID
    public let rank: Int
    public let offeredAt: String
    public let expiresAt: String
    public let status: String

    enum CodingKeys: String, CodingKey {
        case id, rank, status
        case offeredAt = "offered_at"
        case expiresAt = "expires_at"
    }
}

public struct ManufacturingQuote: Codable, Identifiable, Hashable, Equatable, Sendable {
    public let id: UUID
    public let offerId: UUID
    public let requestId: UUID
    public let wholesalerId: UUID
    public let makingChargeMode: String
    public let makingChargeAmount: Double
    public let metalEstimateAmount: Double?
    public let gemstoneEstimateAmount: Double?
    public let otherEstimateAmount: Double?
    public let currency: String
    public let proposedDeliveryDate: String
    public let comments: String?
    public let createdAt: String?
    public let wholesaler: WholesalerBusinessSummary?

    enum CodingKeys: String, CodingKey {
        case id, currency, comments, wholesaler
        case offerId = "offer_id"
        case requestId = "request_id"
        case wholesalerId = "wholesaler_id"
        case makingChargeMode = "making_charge_mode"
        case makingChargeAmount = "making_charge_amount"
        case metalEstimateAmount = "metal_estimate_amount"
        case gemstoneEstimateAmount = "gemstone_estimate_amount"
        case otherEstimateAmount = "other_estimate_amount"
        case proposedDeliveryDate = "proposed_delivery_date"
        case createdAt = "created_at"
    }

    public var parsedMode: MakingBudgetMode {
        MakingBudgetMode(rawValue: makingChargeMode) ?? .perGram
    }

    public var formattedMakingCharge: String {
        switch parsedMode {
        case .perGram:
            return String(format: "₹%.0f/g", makingChargeAmount)
        case .fixedTotal:
            return String(format: "₹%.0f", makingChargeAmount)
        case .percentage:
            return String(format: "%.1f%%", makingChargeAmount)
        }
    }
}

public struct ManufacturingOffer: Codable, Identifiable, Hashable, Equatable, Sendable {
    public let id: UUID
    public let requestId: UUID
    public let rank: Int
    public let status: String
    public let offeredAt: String
    public let expiresAt: String
    public var remainingSeconds: Int
    public var request: ManufacturingRequest?
    public var imageUrl: String?
    public var quote: ManufacturingQuote?
    public let respondedAt: String?
    public let declineReason: String?

    enum CodingKeys: String, CodingKey {
        case id, rank, status, request
        case requestId = "request_id"
        case offeredAt = "offered_at"
        case expiresAt = "expires_at"
        case remainingSeconds = "remaining_seconds"
        case imageUrl = "image_url"
        case quote
        case respondedAt = "responded_at"
        case declineReason = "decline_reason"
    }

    public var parsedStatus: ManufacturingOfferStatus {
        ManufacturingOfferStatus(rawValue: status) ?? .active
    }

    public var isActive: Bool {
        (parsedStatus == .active || parsedStatus == .open) && remainingSeconds > 0
    }
}

public struct CreateManufacturingRequestParams: Encodable, Sendable {
    public let assetId: UUID
    public let category: String
    public let minWeightGrams: Double
    public let maxWeightGrams: Double
    public let material: String
    public let purity: String
    public let gemstonePreference: String
    public let quantity: Int
    public let makingBudgetMode: String
    public let makingBudgetAmount: Double
    public let currency: String
    public let metalRateSnapshot: Double?
    public let metalRateBasis: String?
    public let deliveryNeededDate: String
    public let notes: String?
    public let supersededRequestId: UUID?
    public var quotationWindowHours: Int = 24

    enum CodingKeys: String, CodingKey {
        case category, material, purity, quantity, currency, notes
        case assetId = "asset_id"
        case minWeightGrams = "min_weight_grams"
        case maxWeightGrams = "max_weight_grams"
        case gemstonePreference = "gemstone_preference"
        case makingBudgetMode = "making_budget_mode"
        case makingBudgetAmount = "making_budget_amount"
        case metalRateSnapshot = "metal_rate_snapshot"
        case metalRateBasis = "metal_rate_basis"
        case deliveryNeededDate = "delivery_needed_date"
        case supersededRequestId = "superseded_request_id"
        case quotationWindowHours = "quotation_window_hours"
    }
}

public struct AcceptOfferQuoteParams: Encodable, Sendable {
    public let makingChargeMode: String
    public let makingChargeAmount: Double
    public let metalEstimateAmount: Double?
    public let gemstoneEstimateAmount: Double?
    public let otherEstimateAmount: Double?
    public let proposedDeliveryDate: String
    public let comments: String?
    public let expectedVersion: Int?

    enum CodingKeys: String, CodingKey {
        case comments
        case makingChargeMode = "making_charge_mode"
        case makingChargeAmount = "making_charge_amount"
        case metalEstimateAmount = "metal_estimate_amount"
        case gemstoneEstimateAmount = "gemstone_estimate_amount"
        case otherEstimateAmount = "other_estimate_amount"
        case proposedDeliveryDate = "proposed_delivery_date"
        case expectedVersion = "expected_version"
    }
}
