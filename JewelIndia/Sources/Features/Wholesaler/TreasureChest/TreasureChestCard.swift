import SwiftUI

public struct TreasureChestCard: View {
    @Environment(CreditStore.self) private var credits
    let onOpenTreasureChest: () -> Void
    let onTopUp: () -> Void

    public init(
        onOpenTreasureChest: @escaping () -> Void,
        onTopUp: @escaping () -> Void
    ) {
        self.onOpenTreasureChest = onOpenTreasureChest
        self.onTopUp = onTopUp
    }

    public var body: some View {
        Button(action: onOpenTreasureChest) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xBB8651))

                            Text("Treasure Chest")
                                .font(.manrope(12, weight: .bold))
                                .foregroundStyle(Color(hex: 0xBB8651))
                                .textCase(.uppercase)
                        }

                        if let wallet = credits.wallet {
                            Text("\(wallet.available)")
                                .font(.cirka(34, weight: .bold))
                                .foregroundStyle(Palette.dark)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Palette.muted.opacity(0.2))
                                .frame(width: 60, height: 34)
                                .padding(.vertical, 4)
                        }

                        Text("Credits available")
                            .font(.gilroy(14, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }

                    Spacer(minLength: 12)

                    Button {
                        onTopUp()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Top Up")
                                .font(.manrope(13, weight: .bold))
                        }
                        .foregroundStyle(Palette.dark)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white, in: .rect(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Palette.border, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                    }
                    .buttonStyle(PressableButtonStyle())
                }

                if let wallet = credits.wallet, wallet.expiringSoon > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.statusPending)

                        Text("\(wallet.expiringSoon) credits expiring soon")
                            .font(.manrope(12, weight: .medium))
                            .foregroundStyle(Palette.statusPending)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(Spacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Palette.cream,
                        Color(hex: 0xF7F3EA),
                        Color(hex: 0xFDFBF7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: Radius.xl)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.xl)
                    .stroke(Palette.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }
}
