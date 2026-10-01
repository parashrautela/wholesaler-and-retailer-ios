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
    /// An unavailable balance is never displayed as a fresh spendable amount.
    public private(set) var errorMessage: String?

    /// The retailer's plan; nil for wholesalers and until first loaded.
    public private(set) var plan: PlanStatus?

    public init() {}

    /// Retailers only. Also the renewal tick — see `CreditsAPI.fetchMyPlan`.
    /// A renewal spends credits, so the wallet is refreshed after one.
    public func refreshPlan() async {
        guard let fetched = try? await CreditsAPI.fetchMyPlan() else { return }
        plan = fetched
        if fetched.renewedNow { await refresh() }
    }

    /// Refreshes both wallet balance and the rate card from backend
    public func refresh() async {
        guard !isLoading else { return }
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
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            wallet = nil
            errorMessage = "Couldn't refresh your credit balance."
        }
    }

    /// A server-relative deadline avoids resetting early on a device with a wrong clock.
    public func maintainDailyWallet() async {
        while !Task.isCancelled {
            await refresh()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            func parse(_ raw: String?) -> Date? {
                guard let raw else { return nil }
                return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
            }
            let seconds: Double
            if let deadline = parse(wallet?.resetsAt), let server = parse(wallet?.serverNow) {
                seconds = min(86400, max(1, deadline.timeIntervalSince(server) + 0.25))
            } else { seconds = 60 }
            do { try await Task.sleep(for: .seconds(seconds)) }
            catch { return }
        }
    }

    /// Returns the credit cost for a given feature_key, or nil if unknown
    public func cost(for featureKey: String) -> Int? {
        rateCard[featureKey]?.credits
    }

    #if DEBUG
    func seedPlanForPeek(_ plan: PlanStatus?) { self.plan = plan }

    /// Peeks only: a wallet and rate card without a network or session.
    func seedForPeek(wallet: CreditWallet, rateCard: [CreditPrice]) {
        self.wallet = wallet
        self.rateCardList = rateCard
        self.rateCard = Dictionary(uniqueKeysWithValues: rateCard.map { ($0.featureKey, $0) })
    }
    #endif
}
