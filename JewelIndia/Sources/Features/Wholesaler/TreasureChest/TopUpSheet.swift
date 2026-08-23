import SwiftUI

public struct TopUpSheet: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    private struct CreditPack: Identifiable {
        let id: String
        let name: String
        let credits: Int
        let badge: String?
        let description: String
    }

    private let packs: [CreditPack] = [
        CreditPack(
            id: "starter",
            name: "Starter Pack",
            credits: 50,
            badge: nil,
            description: "Ideal for trying out Chamak fusions and exploring new designs"
        ),
        CreditPack(
            id: "growth",
            name: "Studio Pack",
            credits: 200,
            badge: "Popular",
            description: "Best for active wholesalers launching seasonal collections"
        ),
        CreditPack(
            id: "enterprise",
            name: "Enterprise Pack",
            credits: 1000,
            badge: "Best Value",
            description: "High volume credits for full catalogue transformations"
        )
    ]

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add Credits")
                            .font(.cirka(24, weight: .bold))
                            .foregroundStyle(Palette.dark)

                        Text("Select a credit tier to power your AI jewelry design studio.")
                            .font(.gilroy(14, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }

                    VStack(spacing: Spacing.sm) {
                        ForEach(packs) { pack in
                            packRow(pack)
                        }
                    }

                    // Account manager contact box (no web links / strictly compliant with App Store IAP guidelines)
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(hex: 0xBB8651))

                            Text("Account Manager Assistance")
                                .font(.manrope(14, weight: .bold))
                                .foregroundStyle(Palette.dark)
                        }

                        Text("To add credits to your Treasure Chest wallet or customize an enterprise package, please contact your dedicated Jewel India account manager.")
                            .font(.manrope(13))
                            .foregroundStyle(Palette.dark.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Spacing.base)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.cream, in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Palette.border, lineWidth: 1)
                    }
                }
                .padding(Spacing.base)
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.manrope(14, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                }
            }
        }
    }

    private func packRow(_ pack: CreditPack) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(pack.name)
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(Palette.dark)

                if let badge = pack.badge {
                    Text(badge)
                        .font(.manrope(10, weight: .bold))
                        .foregroundStyle(Color(hex: 0xBB8651))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hex: 0xFFFBF4), in: Capsule())
                        .overlay {
                            Capsule().stroke(Color(hex: 0xF3E8D6), lineWidth: 1)
                        }
                }

                Spacer()

                Text("\(pack.credits) credits")
                    .font(.cirka(18, weight: .bold))
                    .foregroundStyle(Color(hex: 0xBB8651))
            }

            Text(pack.description)
                .font(.manrope(12))
                .foregroundStyle(Palette.muted)
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFAFAFA), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }
}
