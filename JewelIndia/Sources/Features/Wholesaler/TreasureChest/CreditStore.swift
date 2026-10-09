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
    public private(set) var dailySchedule: DailyCreditSchedule?
    public private(set) var walletError: CreditsAPI.WalletError?
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
            // A rate-card outage must not hide a successfully loaded allowance.
            async let rateCardTask = try? CreditsAPI.fetchRateCard()
            let fetchedWallet = try await walletTask

            self.wallet = fetchedWallet
            self.dailySchedule = DailyCreditSchedule(wallet: fetchedWallet)
            self.walletError = nil
            self.errorMessage = nil
            self.lastRefreshed = Date()
            if let fetchedRateCard = await rateCardTask {
                self.rateCardList = fetchedRateCard
                self.rateCard = Dictionary(fetchedRateCard.map { ($0.featureKey, $0) }, uniquingKeysWith: { _, latest in latest })
            }
        } catch {
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            wallet = nil
            dailySchedule = nil
            walletError = error as? CreditsAPI.WalletError
            errorMessage = walletError?.errorDescription ?? "Couldn't refresh your credit balance. Please try again."
        }
    }

    /// A server-relative deadline avoids resetting early on a device with a wrong clock.
    public func maintainDailyWallet() async {
        while !Task.isCancelled {
            await refresh()
            let seconds: Double
            if let schedule = dailySchedule {
                seconds = min(86400, max(1, Double(schedule.remainingSeconds()) + 0.25))
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
        self.dailySchedule = DailyCreditSchedule(wallet: wallet)
        self.walletError = nil
        self.rateCardList = rateCard
        self.rateCard = Dictionary(uniqueKeysWithValues: rateCard.map { ($0.featureKey, $0) })
    }

    func seedWalletErrorForPeek(_ error: CreditsAPI.WalletError) {
        wallet = nil
        dailySchedule = nil
        walletError = error
        errorMessage = error.errorDescription
    }
    #endif
}
