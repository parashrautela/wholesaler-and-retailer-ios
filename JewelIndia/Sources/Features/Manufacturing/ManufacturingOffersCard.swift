import SwiftUI

public struct ManufacturingOffersCard: View {
    var onOpenOffers: () -> Void

    @State private var activeCount: Int = 0
    @State private var isLoading: Bool = false

    public init(onOpenOffers: @escaping () -> Void) {
        self.onOpenOffers = onOpenOffers
    }

    public var body: some View {
        Button(action: onOpenOffers) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Palette.dark)
                        .frame(width: 44, height: 44)

                    Image(systemName: "hammer.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Custom Enquiries")
                            .font(.manrope(15, weight: .bold))
                            .foregroundStyle(Palette.dark)

                        if activeCount > 0 {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Palette.statusPending)
                                    .frame(width: 6, height: 6)
                                Text("\(activeCount) pending")
                                    .font(.manrope(11, weight: .bold))
                                    .foregroundStyle(Palette.statusPending)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.statusPending.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }

                    Text("Exclusive 30-minute turns from verified retailers")
                        .font(.manrope(12, weight: .regular))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(Spacing.base)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(activeCount > 0 ? Palette.statusPending.opacity(0.4) : Palette.border.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .task {
            await checkCount()
        }
    }

    private func checkCount() async {
        do {
            let offers = try await ManufacturingAPI.fetchWholesalerOffers()
            activeCount = offers.filter { $0.isActive }.count
        } catch {
            // Non-critical background count check
        }
    }
}
