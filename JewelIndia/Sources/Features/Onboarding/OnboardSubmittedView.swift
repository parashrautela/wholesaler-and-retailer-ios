import SwiftUI

/// The row the submitted screen reads:
/// `select("verification_status, notification_message, rejection_reason, rejected_documents")`.
struct VerificationRow: Decodable, Sendable {
    let verificationStatus: VerificationStatus?
    let notificationMessage: String?
    let rejectionReason: String?
    let rejectedDocuments: [String]?

    enum CodingKeys: String, CodingKey {
        case verificationStatus = "verification_status"
        case notificationMessage = "notification_message"
        case rejectionReason = "rejection_reason"
        case rejectedDocuments = "rejected_documents"
    }
}

/// `/onboard/submitted` — verification status, and the hand-off to the
/// dashboard once approved.
struct OnboardSubmittedView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var row: VerificationRow?
    @State private var loading = true
    @State private var refreshing = false
    /// A failed status check has to say so. Swallowing it leaves the screen
    /// looking identical to "checked, still pending", which is the one thing
    /// a user waiting on approval must not be told by mistake.
    @State private var refreshError: String?
    @State private var timelineStage = 0   // 0 none · 1 step1 active · 2 step1 done/step2 active · 3 both done

    private var status: VerificationStatus { row?.verificationStatus ?? .pending }

    var body: some View {
        GeometryReader { proxy in
            let gutter = clampVW(16, 3, 48, width: proxy.size.width)

            VStack(spacing: 0) {
                OnboardNavbar(
                    gutter: gutter,
                    showsBack: false,
                    onBack: nil,
                    onRefresh: { await reload() },
                    isRefreshing: refreshing
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        StepIndicator(step: 4, totalSteps: 3)
                            .padding(.bottom, Spacing.xl)

                        Text(heading)
                            .font(.system(size: clampVW(20, 2.2, 28, width: proxy.size.width), weight: .heavy))
                            .foregroundStyle(OnboardColor.heading)
                            .padding(.bottom, 6)

                        Text("we're reviewing your details")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(OnboardColor.subtle)

                        VerificationTimeline(status: status, stage: timelineStage)
                            .frame(maxWidth: 340)
                            .padding(.top, Spacing.xl)
                            .padding(.bottom, Spacing.sm)

                        if isRejection {
                            rejectionPanel
                                .padding(.top, Spacing.xxl)
                        } else {
                            Text(bodyText)
                                .font(.system(size: 14))
                                .foregroundStyle(OnboardColor.subtle)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, Spacing.xl)
                        }

                        if let refreshError {
                            Text(refreshError)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(OnboardColor.danger)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, Spacing.base)
                        }

                        footer(width: proxy.size.width)
                            .padding(.top, Spacing.xxxl)
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, gutter)
                    .padding(.top, clampVW(24, 3, 40, width: proxy.size.width))
                    .padding(.bottom, Spacing.xxxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                // The web re-reads this row on every page load, so a refresh is
                // all it takes to see an approval. A native screen has no such
                // moment — without this, the only way to learn you've been
                // verified is to force-quit and relaunch.
                .refreshable { await reload() }
            }
            .background(Color.white)
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            // Approval lands on an admin's schedule, not the user's. Coming
            // back to the foreground is the moment they'd expect to find out.
            guard phase == .active else { return }
            Task { await reload() }
        }
    }

    // MARK: - Status copy

    private var heading: String {
        switch status {
        case .pending, .onHold: "You're all submitted!"
        case .rejected: "Application Rejected"
        case .resubmissionRequired: "Resubmission Required"
        case .verified: "Verification Complete!"
        case .banned: "Application Rejected"
        }
    }

    private var bodyText: String {
        switch status {
        case .pending:
            "We'll verify your documents in 24–48 hours and notify you on your number once you're approved."
        case .onHold:
            row?.notificationMessage ?? "Your account is on hold pending further review."
        case .verified:
            "You're verified! You can now access your full dashboard."
        case .rejected, .resubmissionRequired, .banned:
            row?.rejectionReason
                ?? row?.notificationMessage
                ?? "There was an issue with your submission. Please click below to resubmit your documents."
        }
    }

    private var buttonTitle: String {
        switch status {
        case .pending, .onHold: "I Understand"
        case .rejected, .resubmissionRequired, .banned: "Resubmit"
        case .verified: "Go to Dashboard"
        }
    }

    private var isRejection: Bool {
        status == .rejected || status == .resubmissionRequired
    }

    // MARK: - Rejection panel

    private var rejectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: 0xDC2626))
                    .padding(8)
                    .background(Color(hex: 0xFEE2E2).opacity(0.7), in: .rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text(status == .rejected ? "Application Rejected" : "Revision Required")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(Color(hex: 0x450A0A))
                    Text(row?.rejectionReason
                        ?? "There was an issue with your submission. Please check the details below and resubmit.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color(hex: 0x991B1B).opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let documents = row?.rejectedDocuments, !documents.isEmpty {
                Divider().overlay(Color(hex: 0xFECACA).opacity(0.6))

                Text("Items to Resubmit:")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(12 * 0.05)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(hex: 0x450A0A).opacity(0.7))

                ForEach(documents, id: \.self) { key in
                    HStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xDC2626))
                        Text(Self.documentName(key))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x7F1D1D))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0xFEE2E2).opacity(0.3), in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: 0xFECACA).opacity(0.5), lineWidth: 1)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(hex: 0xFEF2F2).opacity(0.4), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: 0xFECACA).opacity(0.6), lineWidth: 1)
        }
    }

    /// Document key → display name, from the submitted page's map.
    static func documentName(_ key: String) -> String {
        switch key {
        case "aadhaar_front", "aadhaar_front_url": "Aadhaar Card (Front)"
        case "aadhaar_back", "aadhaar_back_url": "Aadhaar Card (Back)"
        case "pan_card", "pan_card_url": "PAN Card"
        case "gst_certificate", "gst_certificate_url": "GST Certificate"
        case "business_logo", "business_logo_url": "Business Logo"
        default:
            key.replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map(\.capitalized)
                .joined(separator: " ")
        }
    }

    // MARK: - Footer

    private func footer(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            (
                Text("Need help in the meantime? Call us on ")
                    .foregroundColor(OnboardColor.subtle)
                    + Text("9897453396").bold().foregroundColor(OnboardColor.heading)
                    + Text(" — we're happy to assist.").foregroundColor(OnboardColor.subtle)
            )
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await act() }
            } label: {
                Text(loading ? "Loading..." : buttonTitle)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, clampVW(24, 3, 40, width: width))
                    .padding(.vertical, clampVW(10, 1.2, 14, width: width))
                    .background(.black, in: .rect(cornerRadius: 10))
                    .opacity(loading ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(loading)
        }
    }

    // MARK: - Behaviour

    /// First appearance — fetch, then play the timeline in.
    private func load() async {
        row = try? await fetch()
        loading = false

        // Timeline choreography: 50ms → 300ms → 600ms.
        try? await Task.sleep(for: .milliseconds(50))
        withAnimation(Motion.stepFade) { timelineStage = 1 }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(Motion.stepFade) { timelineStage = 2 }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(Motion.stepFade) { timelineStage = 3 }
    }

    /// A re-check: pull-to-refresh, or returning to the foreground.
    ///
    /// Deliberately does not replay the choreography — the timeline is already
    /// on screen, and re-animating it would read as a glitch. A failed fetch
    /// keeps the last known status rather than blanking the screen, so a
    /// dropped connection can't make a verified user look pending again.
    private func reload() async {
        // No session means there is nothing to re-read — reporting "we couldn't
        // find your submission" there would blame the user's data for what is
        // really an absent login.
        guard session.user != nil, !refreshing else { return }
        refreshing = true
        refreshError = nil
        defer { refreshing = false }

        do {
            guard let fresh = try await fetch() else {
                refreshError = "We couldn't find your submission. Please contact support."
                return
            }
            withAnimation(Motion.stepFade) { row = fresh }
        } catch {
            refreshError = "Couldn't check your status. Please try again."
        }
    }

    private func fetch() async throws -> VerificationRow? {
        guard let uid = session.user?.id else { return nil }
        let rows: [VerificationRow] = try await SupabaseManager.client
            .from("wholesalers")
            .select("verification_status, notification_message, rejection_reason, rejected_documents")
            .eq("user_id", value: uid.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// `terminalUserExit(route)` — signs out **only** when the destination is
    /// under `/entry_page`. "Go to Dashboard" and "Resubmit" keep the session.
    private func act() async {
        switch status {
        case .verified:
            // The router sends a `verified` wholesaler here — not to the
            // dashboard — until `has_visited_dashboard` is true, and that flag
            // is only written by the dashboard itself. Refreshing without
            // setting it first just re-resolves to this screen, so the button
            // does nothing. The web doesn't hit this because its "Go to
            // Dashboard" is a plain navigation that reaches the page, which
            // then marks the flag.
            if let user = session.user {
                await WholesalerAPI.markDashboardVisited(userID: user.id)
            }
            await session.refreshDestination()
        case .rejected, .resubmissionRequired:
            await session.refreshDestination()
        case .pending, .onHold, .banned:
            await session.signOut()
        }
    }
}

/// Two-step vertical tracker.
struct VerificationTimeline: View {
    let status: VerificationStatus
    /// 0 none · 1 step-1 active · 2 step-1 done + step-2 active · 3 both settled.
    let stage: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                circle(done: stage >= 2, active: stage == 1, tint: OnboardColor.uploadFilled) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                Rectangle()
                    .fill(stage >= 2 ? OnboardColor.uploadFilled : OnboardColor.border)
                    .frame(width: 2, height: 34)
                    .scaleEffect(y: stage >= 2 ? 1 : 0, anchor: .top)
                    .animation(.easeOut(duration: 0.5), value: stage)
                step2Circle
            }

            VStack(alignment: .leading, spacing: 0) {
                label("Details Submitted", sub: "Under Review", done: stage >= 2, tint: Color(hex: 0x047857))
                    .frame(height: 28 + 34, alignment: .top)
                label(step2Label, sub: step2Sub, done: stage >= 3, tint: step2Tint)
            }

            Spacer(minLength: 0)
        }
    }

    private func circle(
        done: Bool,
        active: Bool,
        tint: Color,
        @ViewBuilder glyph: () -> some View
    ) -> some View {
        ZStack {
            Circle()
                .fill(done ? tint : Color.white)
                .frame(width: 28, height: 28)
            Circle()
                .stroke(done ? tint : (active ? OnboardColor.heading : OnboardColor.border), lineWidth: 2)
                .frame(width: 28, height: 28)
            if done { glyph() }
        }
    }

    private var step2Circle: some View {
        let settled = stage >= 3
        return ZStack {
            Circle().fill(settled ? step2Fill : Color.white).frame(width: 28, height: 28)
            Circle().stroke(settled ? step2Tint : OnboardColor.border, lineWidth: 2).frame(width: 28, height: 28)
            if settled {
                Image(systemName: step2Glyph)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(status == .verified ? .white : step2Tint)
            }
        }
    }

    private func label(_ title: String, sub: String, done: Bool, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14.5, weight: done ? .bold : .medium))
                .foregroundStyle(done ? tint : OnboardColor.subtle)
            Text(sub)
                .font(.system(size: 11.5))
                .foregroundStyle(OnboardColor.subtle)
        }
    }

    // Step-2 presentation, per the status table.
    private var step2Label: String {
        guard stage >= 3 else { return "Verification Status" }
        switch status {
        case .verified: return "Verification Approved"
        case .rejected: return "Application Rejected"
        case .resubmissionRequired: return "Revision Required"
        case .banned: return "Access Suspended"
        case .onHold: return "Application On Hold"
        case .pending: return "Under Verification"
        }
    }

    private var step2Sub: String {
        guard stage >= 3 else { return "Awaiting Analysis" }
        return status == .verified ? "Completed" : "Pending Review"
    }

    private var step2Tint: Color {
        switch status {
        case .verified: Color(hex: 0x22C55E)
        case .rejected, .resubmissionRequired: Color(hex: 0xEF4444)
        case .banned: Color(hex: 0xB91C1C)
        case .onHold, .pending: Color(hex: 0xB45309)
        }
    }

    private var step2Fill: Color {
        switch status {
        case .verified: Color(hex: 0x22C55E)
        case .rejected, .resubmissionRequired: Color(hex: 0xFEF2F2)
        case .banned: Color(hex: 0x450A0A)
        case .onHold, .pending: Color(hex: 0xFFFBEB)
        }
    }

    private var step2Glyph: String {
        switch status {
        case .verified: "checkmark"
        case .rejected, .resubmissionRequired: "exclamationmark.triangle.fill"
        case .banned: "xmark"
        case .onHold, .pending: "clock"
        }
    }
}
