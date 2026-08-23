import SwiftUI

public struct CreditBalancePill: View {
    @Environment(CreditStore.self) private var credits
    let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)

                if let wallet = credits.wallet {
                    Text("\(wallet.available)")
                        .font(.manrope(13, weight: .semibold))
                        .foregroundStyle(textColor)
                } else {
                    // Redacted placeholder to prevent flashing 0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.muted.opacity(0.3))
                        .frame(width: 22, height: 12)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.cream, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var isLowBalance: Bool {
        credits.wallet?.lowBalance == true
    }

    private var iconColor: Color {
        if isLowBalance {
            return Palette.statusPending
        }
        return Color(hex: 0xBB8651)
    }

    private var textColor: Color {
        if isLowBalance {
            return Palette.statusPending
        }
        return Palette.dark
    }

    private var borderColor: Color {
        if isLowBalance {
            return Palette.statusPending.opacity(0.8)
        }
        return Palette.border
    }

    private var accessibilityText: String {
        if let wallet = credits.wallet {
            return "\(wallet.available) credits available"
        }
        return "Loading credit balance"
    }
}
