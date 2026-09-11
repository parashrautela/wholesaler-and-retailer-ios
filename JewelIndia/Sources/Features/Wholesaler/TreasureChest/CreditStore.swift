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
    /// Set when the most recent `refresh()` failed. Previously-loaded wallet
    /// and rate-card data is left in place on failure, so a transient error
    /// doesn't blank out a balance that was already showing.
    public private(set) var errorMessage: String?

    public init() {}

    /// Refreshes both wallet balance and the rate card from backend
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let walletTask = CreditsAPI.fetchWallet()
            async let rateCardTask = CreditsAPI.fetchRateCard()

            let (fetchedWallet, fetchedRateCard) = try await (walletTask, rateCardTask)

            self.wallet = fetchedWallet
            self.rateCardList = fetchedRateCard
            var dict: [String: CreditPrice] = [:]
            for item in fetchedRateCard {
                dict[item.featureKey] = item
            }
            self.rateCard = dict
            self.errorMessage = nil
            self.lastRefreshed = Date()
        } catch {
            errorMessage = "Couldn't refresh your credit balance."
        }
    }

    /// Returns the credit cost for a given feature_key, or nil if unknown
    public func cost(for featureKey: String) -> Int? {
        rateCard[featureKey]?.credits
    }

    #if DEBUG
    /// Peeks only: a wallet and rate card without a network or session.
    func seedForPeek(wallet: CreditWallet, rateCard: [CreditPrice]) {
        self.wallet = wallet
        self.rateCardList = rateCard
        self.rateCard = Dictionary(uniqueKeysWithValues: rateCard.map { ($0.featureKey, $0) })
    }
    #endif
}
