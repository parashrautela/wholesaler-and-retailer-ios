import SwiftUI

/// Invite Retailer sheet (`/dashboard/wholesaler/add-retailer`).
/// Generates and shares retailer invitation links and referral codes.
struct InviteRetailerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var invitation: JewelAPI.RetailerInvitation?
    @State private var isLoading = false
    @State private var error: String?
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

                    Text("Share one secure link. It works for one new retailer and expires after 7 days.")
                        .font(.manrope(14))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }

                if isLoading {
                    ProgressView("Creating secure link…")
                        .font(.manrope(13))
                } else if let invitation {
                    VStack(spacing: Spacing.sm) {
                        Text("YOUR REFERRAL CODE")
                            .font(.manrope(11, weight: .bold))
                            .foregroundStyle(Palette.muted)

                        HStack {
                            Text(invitation.code)
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundStyle(Palette.foreground)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = invitation.link.absoluteString
                                isCopied = true
                                Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    isCopied = false
                                }
                            } label: {
                                Label(isCopied ? "Copied" : "Copy link", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.manrope(12, weight: .bold))
                                    .foregroundStyle(isCopied ? Color.green : Palette.dark)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Palette.cream, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Text("You receive 1,000 credits after the retailer is verified by Jewel India.")
                            .font(.manrope(12))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Spacing.md)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1) }
                } else if let error {
                    VStack(spacing: Spacing.sm) {
                        Text(error)
                            .font(.manrope(13))
                            .foregroundStyle(Color.red)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await generateInvitation() } }
                            .font(.manrope(13, weight: .bold))
                    }
                }

                Spacer()

                if let invitation {
                    ShareLink(
                        item: invitation.link,
                        subject: Text("Join Jewel India"),
                        message: Text("You are invited to join Jewel India as a retailer. Open this link on your iPhone: \(invitation.link.absoluteString)")
                    ) {
                        Label("Share Invitation", systemImage: "square.and.arrow.up")
                            .font(.manrope(15, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Palette.dark, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
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
        .task {
            if invitation == nil { await generateInvitation() }
        }
    }

    private func generateInvitation() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            invitation = try await JewelAPI.createRetailerInvitation()
        } catch {
            self.error = error.localizedDescription
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
                    Text("Invite a retailer to join Jewel India and earn credits after verification.")
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
