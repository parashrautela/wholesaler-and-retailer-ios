import SwiftUI

/// Invite Retailer sheet (`/dashboard/wholesaler/add-retailer`).
/// Generates and shares retailer invitation links and referral codes.
struct InviteRetailerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session

    @State private var referralCode: String = "JI-" + String(UUID().uuidString.prefix(6)).uppercased()
    @State private var isCopied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                Spacer()

                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(Palette.dark)

                VStack(spacing: Spacing.xs) {
                    Text("Invite Retailer")
                        .font(.cirka(28))
                        .foregroundStyle(Palette.foreground)

                    Text("Share this referral code or link with retailers so they can connect to your catalogue.")
                        .font(.manrope(14))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }

                // Code Card
                VStack(spacing: Spacing.sm) {
                    Text("YOUR REFERRAL CODE")
                        .font(.manrope(11, weight: .bold))
                        .foregroundStyle(Palette.muted)

                    HStack {
                        Text(referralCode)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(Palette.foreground)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = referralCode
                            isCopied = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                isCopied = false
                            }
                        } label: {
                            Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.manrope(12, weight: .bold))
                                .foregroundStyle(isCopied ? Color.green : Palette.dark)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Palette.cream, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Spacing.md)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1) }
                }

                Spacer()

                ShareLink(
                    item: URL(string: "https://app.jewelindia.shop/join/\(referralCode)")!,
                    subject: Text("Join Jewel India"),
                    message: Text("Use my code \(referralCode) to connect with our wholesale catalogue on Jewel India!")
                ) {
                    Label("Share Invitation Link", systemImage: "square.and.arrow.up")
                        .font(.manrope(15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.dark, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.screenGutter)
            .navigationTitle("Invite Retailer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Entry Points

/// The compact call to action, for empty states (Orders, Chat) where having
/// no retailers is the likely reason the screen is empty.
struct InviteRetailerButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Invite a Retailer", systemImage: "person.crop.circle.badge.plus")
                .font(.manrope(14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Palette.dark, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// The Home card — same frame as the Insights `StatCard`s it sits under.
struct InviteRetailerCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.base) {
                Image("NavAddRetailer")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Palette.dark)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: 0xFFFBF4), in: .circle)
                    .overlay { Circle().stroke(Color(hex: 0xF3E8D6), lineWidth: 1) }

                VStack(alignment: .leading, spacing: 3) {
                    Text(Copy.WholesalerTab.inviteRetailer)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x111827))
                    Text("Share your code so retailers can browse your catalogue and order.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0x6B7280))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: 0x9CA3AF))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: 0xE5E5E5), lineWidth: 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}
