import Foundation
import Observation

@MainActor
@Observable
public final class CreditStore {
    public private(set) var wallet: CreditWallet?
    public private(set) var rateCard: [String: CreditPrice] = [:] // keyed by feature_key
    public private(set) var rateCardList: [CreditPrice] = []
    public private(set) var isLoading: Bool = false
    public private(set) var lastRefreshed: Date?

    public init() {}

    /// Refreshes both wallet balance and the rate card from backend
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let walletTask = try? await CreditsAPI.fetchWallet()
        async let rateCardTask = try? await CreditsAPI.fetchRateCard()

        let (fetchedWallet, fetchedRateCard) = await (walletTask, rateCardTask)

        if let fetchedWallet {
            self.wallet = fetchedWallet
        }

        if let fetchedRateCard {
            self.rateCardList = fetchedRateCard
            var dict: [String: CreditPrice] = [:]
            for item in fetchedRateCard {
                dict[item.featureKey] = item
            }
            self.rateCard = dict
        }

        self.lastRefreshed = Date()
    }

    /// Returns the credit cost for a given feature_key, or nil if unknown
    public func cost(for featureKey: String) -> Int? {
        rateCard[featureKey]?.credits
    }
}
