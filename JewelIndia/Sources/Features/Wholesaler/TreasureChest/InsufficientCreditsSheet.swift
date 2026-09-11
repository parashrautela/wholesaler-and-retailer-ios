import SwiftUI

struct InsufficientCreditsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let error: ChamakAPI.InsufficientCreditsError?

    @State private var topUp = TopUpModel()
    @State private var isShowingTopUp = false

    init(error: ChamakAPI.InsufficientCreditsError?) {
        self.error = error
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header with icon
                HStack(alignment: .top, spacing: Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0xFEF3C7))
                            .frame(width: 44, height: 44)

                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xD97706))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("More Credits Needed")
                            .font(.cirka(20, weight: .bold))
                            .foregroundStyle(Palette.dark)

                        if let error {
                            Text("You need \(TopUpStyle.count(error.shortBy)) more credits to generate this Chamak fusion.")
                                .font(.manrope(13))
                                .foregroundStyle(Palette.muted)
                        } else {
                            Text("You do not have enough credits in your Treasure Chest for this generation.")
                                .font(.manrope(13))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }

                if let error {
                    balanceSummary(error)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0xBB8651))

                    Text("Your sliders and artisan notes are saved. Buy credits and carry on right where you left off.")
                        .font(.manrope(12))
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

                Spacer()

                VStack(spacing: Spacing.sm) {
                    Button {
                        isShowingTopUp = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 15))
                            Text("Buy Credits")
                                .font(.manrope(15, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.dark, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(PressableButtonStyle())

                    Button {
                        dismiss()
                    } label: {
                        Text("Back to Editor")
                            .font(.manrope(14, weight: .bold))
                            .foregroundStyle(Palette.dark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white, in: .rect(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Palette.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(Spacing.base)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                }
            }
            .navigationDestination(isPresented: $isShowingTopUp) {
                TopUpView(model: topUp, doneTitle: "Back to Editor") { dismiss() }
            }
        }
    }

    private func balanceSummary(_ error: ChamakAPI.InsufficientCreditsError) -> some View {
        HStack(spacing: Spacing.md) {
            summaryValue("Current Balance", error.balance, tint: Palette.dark, labelTint: Palette.muted)
            Divider()
            summaryValue("Required", error.required, tint: Palette.dark, labelTint: Palette.muted)
            Divider()
            summaryValue("Short By", error.shortBy, tint: Color(hex: 0xD97706), labelTint: Color(hex: 0xD97706))
        }
        // Dividers stretch to whatever height is going, which made the box
        // swallow the sheet.
        .fixedSize(horizontal: false, vertical: true)
        .padding(Spacing.base)
        .background(Color(hex: 0xF9FAFB), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private func summaryValue(_ label: String, _ value: Int, tint: Color, labelTint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.manrope(11, weight: .semibold))
                .foregroundStyle(labelTint)

            Text(TopUpStyle.count(value))
                .font(.cirka(22, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
