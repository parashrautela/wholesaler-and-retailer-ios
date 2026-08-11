import SwiftUI

/// `/onboard-retailer/submitted` — the retailer counterpart of
/// `OnboardSubmittedView`.
///
/// Until now `RootView` pointed `.retailerSubmitted` at `OnboardSubmittedView`
/// itself, which queries `wholesalers`. For a retailer that query always
/// returns no row, so `status` fell back to its `.pending` default forever —
/// a verified retailer would see "under review" no matter how many times they
/// refreshed, because the screen was reading the wrong table entirely.
///
/// `VerificationRow`, `VerificationTimeline`, and the rejected-document name
/// mapping are shared with the wholesaler screen (declared in
/// `OnboardSubmittedView.swift`, not `private`) since the `retailers` and
/// `wholesalers` tables carry the identical status/rejection columns.
struct RetailerOnboardSubmittedView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var row: VerificationRow?
    @State private var loading = true
    @State private var refreshing = false
    @State private var refreshError: String?
    @State private var timelineStage = 0

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
                .refreshable { await reload() }
            }
            .background(Color.white)
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
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
                        Text(OnboardSubmittedView.documentName(key))
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

    private func load() async {
        row = try? await fetch()
        loading = false

        try? await Task.sleep(for: .milliseconds(50))
        withAnimation(Motion.stepFade) { timelineStage = 1 }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(Motion.stepFade) { timelineStage = 2 }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(Motion.stepFade) { timelineStage = 3 }
    }

    private func reload() async {
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
            .from("retailers")
            .select("verification_status, notification_message, rejection_reason, rejected_documents")
            .eq("user_id", value: uid.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private func act() async {
        switch status {
        case .verified:
            // Same "dead button" trap as the wholesaler screen: the router
            // holds a verified-but-unvisited retailer here until this flag is
            // set, and refreshing without setting it first just re-resolves
            // back to this same screen.
            if let user = session.user {
                await RetailerAPI.markDashboardVisited(userID: user.id)
            }
            // Per `_spec/06-retailer-screens.md` §0, a freshly verified
            // retailer has no `jewel_view_mode` cookie yet, so the router's
            // default (mirrored by `ViewModeStore`) lands on the employee
            // dashboard, not the retailer one, until they explicitly switch —
            // reproduced rather than "corrected" here.
            await session.refreshDestination()
        case .rejected, .resubmissionRequired:
            await session.refreshDestination()
        case .pending, .onHold, .banned:
            await session.signOut()
        }
    }
}
