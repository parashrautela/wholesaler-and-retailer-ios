import SwiftUI

/// Subscription plans, bought with credits. The server owns the rules — what
/// a plan costs, when one may be bought, when it renews — so this screen only
/// shows what it is told and asks.
struct PlansView: View {
    @Environment(CreditStore.self) private var credits

    @State private var plans: [Plan] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var confirming: Plan?
    @State private var buyingKey: String?
    @State private var notice: String?
    @State private var showTopUp = false

    #if DEBUG
    /// Peeks only: plans to show instead of fetching.
    var peekPlans: [Plan]?
    #endif

    private var status: PlanStatus? { credits.plan }
    private var balance: Int { credits.wallet?.available ?? 0 }

    /// The server allows extending only in the last week of cover.
    private var canBuy: Bool {
        guard let status, status.active, let expires = status.expiresAt else { return true }
        return expires < Date().addingTimeInterval(7 * 24 * 60 * 60)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                statusCard

                if isLoading && plans.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xxl)
                } else if let errorMessage, plans.isEmpty {
                    VStack(spacing: Spacing.sm) {
                        Text(errorMessage)
                            .font(.manrope(13))
                            .foregroundStyle(Palette.muted)
                        Button("Try Again") { Task { await load() } }
                            .font(.manrope(13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.xxl)
                } else {
                    ForEach(plans) { plan in
                        planCard(plan)
                    }

                    Text("Plans are paid for with credits and renew from your balance. If there aren't enough credits when a plan ends, it simply stops — nothing is charged to a card.")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.base)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showTopUp) {
            TopUpSheet()
                .environment(credits)
        }
        .confirmationDialog(
            confirming.map { "Start the \($0.label) plan?" } ?? "",
            isPresented: Binding(
                get: { confirming != nil },
                set: { if !$0 { confirming = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let plan = confirming {
                Button("Pay \(TopUpStyle.count(credits.cost(for: plan.priceKey) ?? 0)) Credits") {
                    Task { await buy(plan) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let plan = confirming {
                Text("\(plan.periodDays) days, paid from your \(TopUpStyle.count(balance)) credits. It renews from your balance until you turn that off.")
            }
        }
        .alert(notice ?? "", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Current plan

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let status, status.active {
                Text("\(label(for: status.planKey)) plan")
                    .font(.cirka(26))
                    .foregroundStyle(.white)
                if let expires = status.expiresAt {
                    Text("\(status.autoRenew ? "Renews" : "Ends") \(expires.formatted(date: .abbreviated, time: .omitted))")
                        .font(.manrope(13))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Toggle(isOn: Binding(
                    get: { status.autoRenew },
                    set: { on in Task { await setAutoRenew(on) } }
                )) {
                    Text("Renew from my credits")
                        .font(.manrope(13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .tint(ThemePalette.amber)
                .padding(.top, 4)
            } else {
                Text("No plan yet")
                    .font(.cirka(26))
                    .foregroundStyle(.white)
                Text(lapsedLine ?? "Pick a plan below. You have \(TopUpStyle.count(balance)) credits.")
                    .font(.manrope(13))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.dark, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Why a plan that should have renewed didn't.
    private var lapsedLine: String? {
        guard let status, !status.active, status.planKey != nil else { return nil }
        if status.renewalError == "INSUFFICIENT_CREDITS" {
            return "Your \(label(for: status.planKey)) plan ended — there weren't enough credits to renew it."
        }
        return "Your \(label(for: status.planKey)) plan has ended."
    }

    private func label(for key: String?) -> String {
        plans.first { $0.key == key }?.label ?? key?.capitalized ?? ""
    }

    // MARK: - Plan cards

    private func planCard(_ plan: Plan) -> some View {
        let price = credits.cost(for: plan.priceKey)
        let isCurrent = status?.active == true && status?.planKey == plan.key
        let isShort = (price ?? 0) > balance

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.label)
                    .font(.cirka(22))
                    .foregroundStyle(Palette.foreground)
                if isCurrent {
                    Text("CURRENT")
                        .font(.manrope(10, weight: .bold))
                        .kerning(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ThemePalette.emerald, in: Capsule())
                }
                Spacer()
                if let price {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(TopUpStyle.count(price))
                            .font(.manrope(18, weight: .bold))
                            .foregroundStyle(Palette.foreground)
                        Text("credits · \(plan.periodDays) days")
                            .font(.manrope(11))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.perks, id: \.self) { perk in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ThemePalette.emerald)
                            .padding(.top, 3)
                        Text(perk)
                            .font(.manrope(13))
                            .foregroundStyle(Palette.foreground)
                    }
                }
            }

            if price != nil, canBuy {
                Button {
                    if isShort { showTopUp = true } else { confirming = plan }
                } label: {
                    HStack(spacing: 8) {
                        if buyingKey == plan.key {
                            ProgressView().tint(.white).controlSize(.small)
                        }
                        Text(buttonTitle(isCurrent: isCurrent, isShort: isShort))
                            .font(.manrope(13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.dark, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(buyingKey != nil)
                .opacity(buyingKey != nil && buyingKey != plan.key ? 0.5 : 1)
            }
        }
        .padding(Spacing.lg)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrent ? ThemePalette.emerald : Color.clear, lineWidth: 1.5)
        }
    }

    private func buttonTitle(isCurrent: Bool, isShort: Bool) -> String {
        if isShort { return "Top Up to Subscribe" }
        if status?.active == true { return isCurrent ? "Extend" : "Switch When This Ends" }
        return "Subscribe"
    }

    // MARK: - Actions

    private func load() async {
        #if DEBUG
        if let peekPlans {
            plans = peekPlans
            isLoading = false
            return
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetched = CreditsAPI.fetchPlans()
            async let plan: Void = credits.refreshPlan()
            plans = try await fetched
            _ = await plan
            errorMessage = nil
        } catch {
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            errorMessage = "Couldn't load plans."
        }
    }

    private func buy(_ plan: Plan) async {
        guard buyingKey == nil else { return }
        buyingKey = plan.key
        defer { buyingKey = nil }
        do {
            let result = try await CreditsAPI.subscribe(planKey: plan.key)
            if result.ok {
                await credits.refresh()
                await credits.refreshPlan()
            } else if result.isInsufficientCredits {
                await credits.refresh()
                notice = "You need \(TopUpStyle.count(result.shortBy ?? 0)) more credits for this plan."
            } else if result.error == "ALREADY_ACTIVE" {
                await credits.refreshPlan()
                notice = "Your plan is already active. You can extend it in its last week."
            } else if result.error == "NOT_VERIFIED" {
                notice = "Your store needs to be verified before you can start a plan."
            } else {
                notice = "This plan can't be started right now. Please try again."
            }
        } catch {
            // The purchase may have gone through; the server refuses a second
            // one, so checking is safe and a retry can't charge twice.
            await credits.refresh()
            await credits.refreshPlan()
            if credits.plan?.active != true {
                notice = "Couldn't reach the server. Please try again — you won't be charged twice."
            }
        }
    }

    private func setAutoRenew(_ on: Bool) async {
        do {
            try await CreditsAPI.setPlanAutoRenew(on)
            await credits.refreshPlan()
        } catch {
            notice = "Couldn't change that. Please try again."
        }
    }
}
