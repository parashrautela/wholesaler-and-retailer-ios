import SwiftUI

/// Invite Retailer sheet matching Figma design node 3156:1821.
/// Displays reward banner, points stepper for onboarding retailers,
/// the active invitation code with copy button, and the primary "Invite retailer now" share button.
struct InviteRetailerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CreditStore.self) private var credits
    @State private var invitation: JewelAPI.RetailerInvitation?
    @State private var pointsOffered: Int = 1000
    @State private var busy = false
    @State private var copied = false
    @State private var error: String?
    @State private var showShareSheet = false
    var previewStage: Int? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Top Banner Card (Figma Node 3156:1826)
                topRewardCard

                // Subtitle / Heading (Figma Node 3156:1834)
                Text("Help a retailer discover a better way to do jewellery business.")
                    .font(.manrope(16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2E2D2A))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Stepper Row (Figma Node 3156:1836)
                VStack(alignment: .leading, spacing: 8) {
                    stepperView

                    // Note below stepper (Figma Node 3156:1835)
                    Text("(Give them a head start with points from your wallet.)")
                        .font(.manrope(12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x949494))
                }

                // Active invitation code display with copy button
                if let invitation {
                    invitationCodeCard(invitation)
                }

                if let error {
                    Text(error)
                        .font(.manrope(12))
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                // Primary Action Button: "Invite retailer now"
                inviteNowButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .background(Color(hex: 0xF1F2F3))
        .presentationCornerRadius(32)
        .presentationDragIndicator(.visible)
        .task {
            await initialize()
        }
        .sheet(isPresented: $showShareSheet) {
            if let invitation {
                ShareActivityView(activityItems: [
                    "You are invited to join Jewel India as a retailer! Use code \(invitation.code) to get \(pointsOffered) points. Open link: \(invitation.link.absoluteString)",
                    invitation.link
                ])
            }
        }
    }

    // MARK: - Subviews

    private var topRewardCard: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Earn 1000 points")
                        .font(.manrope(12, weight: .bold))
                        .foregroundStyle(Color(hex: 0x2E2D2A))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(hex: 0xE9E9E9), lineWidth: 1))

                    Spacer(minLength: 16)

                    Text("Grow your network.\nGet rewarded.")
                        .font(.cirka(24, weight: .bold))
                        .foregroundStyle(Color(hex: 0x2E2D2A))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("For each retailer who joins")
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x949494))
                        .padding(.top, 4)
                }
                .padding(14)

                Spacer(minLength: 0)
            }

            Image("InviteRewardArtwork")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 170)
                .clipped()
        }
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 170)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(hex: 0xE9E9E9), lineWidth: 1)
        )
        .shadow(color: Color(hex: 0x707070).opacity(0.18), radius: 12, x: 2, y: 3)
    }

    private var stepperView: some View {
        HStack(spacing: 0) {
            Button {
                if pointsOffered >= 250 {
                    pointsOffered -= 250
                }
            } label: {
                Image("InviteMinus")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(pointsOffered <= 0 ? Color(hex: 0xC0C0C0) : Color(hex: 0x555555))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(pointsOffered <= 0)

            Rectangle()
                .fill(Color(hex: 0xEDEDED))
                .frame(width: 1, height: 32)

            Text("\(pointsOffered)")
                .font(.manrope(16, weight: .bold))
                .foregroundStyle(Color(hex: 0x2E2D2A))
                .frame(width: 58)
                .multilineTextAlignment(.center)

            Rectangle()
                .fill(Color(hex: 0xEDEDED))
                .frame(width: 1, height: 32)

            Button {
                pointsOffered += 250
            } label: {
                Image("InvitePlus")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color(hex: 0x555555))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 152, height: 44)
        .background(Color.white)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(hex: 0xEDEDED), lineWidth: 1))
    }

    private func invitationCodeCard(_ invitation: JewelAPI.RetailerInvitation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR INVITATION CODE")
                    .font(.manrope(10, weight: .bold))
                    .foregroundStyle(Color(hex: 0x949494))
                    .tracking(0.5)

                Text(invitation.code)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x2E2D2A))
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                UIPasteboard.general.string = invitation.link.absoluteString
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .bold))
                    Text(copied ? "Copied" : "Copy link")
                        .font(.manrope(12, weight: .bold))
                }
                .foregroundStyle(copied ? Color(hex: 0x16A34A) : Color(hex: 0x2E2D2A))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(hex: 0xF1F2F3), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: 0xE0E0E0), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: 0xE9E9E9), lineWidth: 1)
        )
    }

    private var inviteNowButton: some View {
        Button {
            Task { await handleInviteNow() }
        } label: {
            HStack(spacing: 10) {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text("Invite retailer now")
                        .font(.manrope(16, weight: .bold))
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x4F4F4F), Color(hex: 0x232323)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(busy)
    }

    // MARK: - Actions

    @MainActor private func initialize() async {
        if previewStage != nil {
            invitation = JewelAPI.RetailerInvitation(
                id: "preview-id",
                code: "PJ-b61rce",
                link: URL(string: "https://jewelindia.shop/join/PJ-b61rce")!,
                expiresAt: "2026-10-12",
                giftCredits: 1000,
                extraCredits: 0,
                status: "unclaimed",
                fundingState: nil,
                retailerName: nil,
                generationKey: nil,
                refundedCredits: nil
            )
            return
        }

        do {
            if let existing = try await JewelAPI.fetchLatestActiveInvitation() {
                self.invitation = existing
            } else {
                self.invitation = try await JewelAPI.createRetailerInvitation(gift: pointsOffered)
            }
        } catch {
            // Non-fatal on load; user can tap button to retry
        }
    }

    @MainActor private func handleInviteNow() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let inv: JewelAPI.RetailerInvitation
            if let existing = invitation {
                inv = existing
            } else {
                inv = try await JewelAPI.createRetailerInvitation(gift: pointsOffered)
                self.invitation = inv
            }
            UIPasteboard.general.string = inv.link.absoluteString
            copied = true
            showShareSheet = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Helpers

struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct InvitationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CreditStore.self) private var credits
    @State private var links: [JewelAPI.RetailerInvitation] = []
    @State private var page = 0
    @State private var count = 0
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section {
                        Text(error).font(.manrope(13)).foregroundStyle(Color.red)
                    }
                }
                Section {
                    if links.isEmpty && !busy {
                        Text("No active invitations").font(.manrope(14)).foregroundStyle(Palette.muted)
                    }
                    ForEach(links, id: \.id) { link in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(link.code).font(.system(size: 16, weight: .bold, design: .monospaced))
                                Spacer()
                                Text(link.status ?? "unclaimed").font(.manrope(12, weight: .bold)).foregroundStyle(link.status == "accepted" ? Color.green : Palette.muted)
                            }
                            Text("Expires \(formattedDate(link.expiresAt))").font(.manrope(12)).foregroundStyle(Palette.muted)
                        }
                        .swipeActions(edge: .trailing) {
                            if link.status == "unclaimed" {
                                Button("Cancel", role: .destructive) {
                                    Task { await cancel(link.id) }
                                }
                            }
                        }
                    }
                }
                if count > 20 {
                    HStack {
                        Button("Previous") { page -= 1; Task { await load() } }.disabled(page == 0 || busy)
                        Spacer()
                        Button("Next") { page += 1; Task { await load() } }.disabled((page + 1) * 20 >= count || busy)
                    }
                }
            }
            .overlay { if busy { ProgressView() } }
            .navigationTitle("Your invitations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func formattedDate(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: raw)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: raw)
        }
        guard let d = date else { return raw }
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        return displayFormatter.string(from: d)
    }

    @MainActor private func load() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let data = try await JewelAPI.invitationSettings(page: page)
            links = data.links ?? []
            count = data.count ?? 0
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor private func cancel(_ id: String) async {
        busy = true
        do {
            try await JewelAPI.cancelInvitation(id: id)
            await load()
        } catch {
            self.error = error.localizedDescription
            busy = false
        }
    }
}

struct InviteRetailerButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label("Invite a Retailer", systemImage: "person.crop.circle.badge.plus").font(.manrope(14, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 10).background(Palette.dark, in: .rect(cornerRadius: 8)) }
            .buttonStyle(PressableButtonStyle())
    }
}

struct InviteRetailerCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleHeight = 24
    @ScaledMetric(relativeTo: .body) private var copyLineHeight = 17.5
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image("InviteUserPlus").resizable().scaledToFit().frame(width: 54, height: 55).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Invite retailers")
                        .font(.cirka(24, weight: .bold))
                        .foregroundStyle(Color(hex: 0x2E2D2A))
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : titleHeight)
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            Text("Invite Retailer to join your network on JewelIndia")
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Invite Retailer to join your").frame(height: copyLineHeight)
                                Text("network on JewelIndia").frame(height: copyLineHeight)
                            }
                        }
                    }
                    .font(.manrope(14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x949494))
                }.frame(width: 175, alignment: .leading)
                Spacer(minLength: 0)
            }.padding(16).frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
                .background {
                    GeometryReader { geometry in
                        let scale = min(geometry.size.width / 393, 1)
                        Image("InviteCardArtwork").resizable().scaledToFit()
                            .frame(width: 154 * scale, height: 98 * scale)
                            .mask { UnevenRoundedRectangle(bottomTrailingRadius: 20, topTrailingRadius: 20).padding(.vertical, 2).padding(.trailing, 2) }
                            .position(x: geometry.size.width - 77 * scale, y: geometry.size.height / 2)
                    }
                }
                .background(LinearGradient(colors: [Color(hex: 0xF1F2F3), Color(hex: 0xFED77D)], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color(hex: 0xD0D0D0), lineWidth: 1) }
        }.buttonStyle(PressableButtonStyle())
    }
}
