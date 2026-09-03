import SwiftUI

struct InsufficientCreditsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let error: ChamakAPI.InsufficientCreditsError?

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
                            Text("You need \(error.shortBy) more credits to generate this Chamak fusion.")
                                .font(.manrope(13))
                                .foregroundStyle(Palette.muted)
                        } else {
                            Text("You do not have enough credits in your Treasure Chest for this generation.")
                                .font(.manrope(13))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }

                // Balance summary box
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Balance")
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(Palette.muted)

                        Text("\(error?.balance ?? 0)")
                            .font(.cirka(22, weight: .bold))
                            .foregroundStyle(Palette.dark)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Required")
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(Palette.muted)

                        Text("\(error?.required ?? 10)")
                            .font(.cirka(22, weight: .bold))
                            .foregroundStyle(Palette.dark)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Short By")
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xD97706))

                        Text("\(error?.shortBy ?? 0)")
                            .font(.cirka(22, weight: .bold))
                            .foregroundStyle(Color(hex: 0xD97706))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Spacing.base)
                .background(Color(hex: 0xF9FAFB), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
                }

                // Account manager callout (Rule §2.6 - compliant with App Store guidelines)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: 0xBB8651))

                        Text("Top Up Your Treasure Chest")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Palette.dark)
                    }

                    Text("Contact your account manager to add credits. Your sliders and artisan notes have been saved so you can continue immediately.")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.dark.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.base)
                .background(Palette.cream, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Palette.border, lineWidth: 1)
                }

                Spacer()

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
            .padding(Spacing.base)
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
        }
    }
}
