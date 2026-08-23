import SwiftUI

public struct TreasureChestView: View {
    @Environment(CreditStore.self) private var credits
    @State private var showTopUpSheet = false
    @State private var recentEntries: [CreditLedgerEntry] = []
    @State private var isLoadingLedger = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                balanceHero
                statsRow

                if let wallet = credits.wallet, wallet.expiringSoon > 0 {
                    expiringNotice(wallet)
                }

                topUpSection
                rateCardSection
                recentActivitySection
            }
            .padding(.horizontal, Spacing.base)
            .padding(.top, Spacing.base)
            .padding(.bottom, Spacing.huge)
        }
        .background(Color(hex: 0xFAFAFA))
        .navigationTitle("Treasure Chest")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await reload()
        }
        .task {
            await reload()
        }
        .sheet(isPresented: $showTopUpSheet) {
            TopUpSheet()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - 1. Balance Hero

    private var balanceHero: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xBB8651))

                Text("Available Balance")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color(hex: 0xBB8651))
                    .textCase(.uppercase)
            }

            if let wallet = credits.wallet {
                Text("\(wallet.available)")
                    .font(.cirka(48, weight: .bold))
                    .foregroundStyle(Palette.dark)
            } else {
                ProgressView()
                    .frame(height: 58)
            }

            Text("Credits available for AI jewelry generation")
                .font(.gilroy(14, weight: .medium))
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.base)
        .background(
            LinearGradient(
                colors: [Palette.cream, Color(hex: 0xF7F3EA), Color(hex: 0xFDFBF7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Palette.border, lineWidth: 1)
        }
    }

    // MARK: - 2. Three Stats Row

    private var statsRow: some View {
        HStack(spacing: Spacing.sm) {
            statTile(
                title: "Granted",
                value: "\(credits.wallet?.lifetimeGranted ?? 0)",
                symbol: "gift.fill",
                color: Color(hex: 0x059669)
            )

            statTile(
                title: "Used",
                value: "\(credits.wallet?.lifetimeSpent ?? 0)",
                symbol: "sparkles",
                color: Color(hex: 0xBB8651)
            )

            statTile(
                title: "Expired",
                value: "\(credits.wallet?.lifetimeExpired ?? 0)",
                symbol: "clock.badge.xmark",
                color: Palette.muted
            )
        }
    }

    private func statTile(title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
            }

            Text(value)
                .font(.cirka(20, weight: .bold))
                .foregroundStyle(Palette.dark)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Palette.border, lineWidth: 1)
        }
    }

    // MARK: - 3. Expiring Notice

    private func expiringNotice(_ wallet: CreditWallet) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 16))
                .foregroundStyle(Palette.statusPending)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(wallet.expiringSoon) credits expiring soon")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Palette.statusPending)

                Text("Use your expiring balance to fuse new designs or re-roll variants.")
                    .font(.manrope(12))
                    .foregroundStyle(Color(hex: 0x92400E))
            }
            Spacer()
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFFBEB), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xFDE68A), lineWidth: 1)
        }
    }

    // MARK: - 4. Top Up CTA

    private var topUpSection: some View {
        Button {
            showTopUpSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                Text("Add More Credits")
                    .font(.manrope(14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.dark, in: .rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - 5. Rate Card ("What things cost")

    private var rateCardSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("What Things Cost")
                .font(.cirka(20, weight: .bold))
                .foregroundStyle(Palette.dark)

            Text("Credit costs per action. Read directly from your live rate card.")
                .font(.manrope(12))
                .foregroundStyle(Palette.muted)

            VStack(spacing: 0) {
                // Filter out 0 cost items to eliminate noise (Rule §1.1)
                let activePaid = credits.rateCardList.filter { $0.credits > 0 }

                if activePaid.isEmpty {
                    HStack {
                        Text("Rate card updating...")
                            .font(.manrope(13))
                            .foregroundStyle(Palette.muted)
                        Spacer()
                    }
                    .padding(Spacing.base)
                } else {
                    ForEach(Array(activePaid.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label)
                                    .font(.manrope(14, weight: .semibold))
                                    .foregroundStyle(Palette.dark)

                                if let desc = item.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.manrope(12))
                                        .foregroundStyle(Palette.muted)
                                }
                            }

                            Spacer()

                            Text("\(item.credits) credits")
                                .font(.manrope(13, weight: .bold))
                                .foregroundStyle(Color(hex: 0xBB8651))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: 0xFFFBF4), in: Capsule())
                                .overlay {
                                    Capsule().stroke(Color(hex: 0xF3E8D6), lineWidth: 1)
                                }
                        }
                        .padding(.horizontal, Spacing.base)
                        .padding(.vertical, 12)

                        if index < activePaid.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .background(Color.white, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Palette.border, lineWidth: 1)
            }
        }
    }

    // MARK: - 6. Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Recent Activity")
                    .font(.cirka(20, weight: .bold))
                    .foregroundStyle(Palette.dark)

                Spacer()

                NavigationLink {
                    TransactionHistoryView()
                } label: {
                    HStack(spacing: 4) {
                        Text("See All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color(hex: 0xBB8651))
                }
            }

            VStack(spacing: 0) {
                if isLoadingLedger && recentEntries.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(Spacing.base)
                        Spacer()
                    }
                } else if recentEntries.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.system(size: 24))
                            .foregroundStyle(Palette.muted)
                        Text("No activity yet. Your credits will appear here as you use them.")
                            .font(.manrope(13))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.xl)
                } else {
                    ForEach(Array(recentEntries.prefix(6).enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(item.delta > 0 ? Color(hex: 0xECFDF5) : Color(hex: 0xF3F4F6))
                                    .frame(width: 32, height: 32)

                                Image(systemName: item.delta > 0 ? "arrow.down.left" : "arrow.up.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(item.delta > 0 ? Color(hex: 0x059669) : Palette.dark)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayTitle)
                                    .font(.manrope(13, weight: .semibold))
                                    .foregroundStyle(Palette.dark)

                                if let date = item.date {
                                    Text(relativeDateString(from: date))
                                        .font(.sfPro(11))
                                        .foregroundStyle(Palette.muted)
                                }
                            }

                            Spacer()

                            Text(item.delta > 0 ? "+\(item.delta)" : "\(item.delta)")
                                .font(.manrope(14, weight: .bold))
                                .foregroundStyle(item.delta > 0 ? Color(hex: 0x059669) : Palette.dark)
                        }
                        .padding(.horizontal, Spacing.base)
                        .padding(.vertical, 10)

                        if index < min(recentEntries.count, 6) - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
            .background(Color.white, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Palette.border, lineWidth: 1)
            }
        }
    }

    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func reload() async {
        isLoadingLedger = true
        defer { isLoadingLedger = false }

        async let walletTask: Void = credits.refresh()
        async let ledgerTask = try? await CreditsAPI.fetchLedger(limit: 20)

        let (_, ledger) = await (walletTask, ledgerTask)
        if let ledger {
            self.recentEntries = ledger
        }
    }
}
