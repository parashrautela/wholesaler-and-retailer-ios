import SwiftUI

/// The one-time onboarding fee, asked for when a wholesaler submits their
/// application. Razorpay's page opens in-app; when it closes, the payment is
/// confirmed with the server and the application goes on its way.
struct OnboardingFeeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let amountINR: Int
    /// Called once the fee is confirmed paid.
    let onPaid: () -> Void

    private enum Phase: Equatable {
        case ready, opening, checking, notYet, failed(String)
    }

    @State private var phase: Phase = .ready
    @State private var link: OnboardingFeeAPI.Link?
    @State private var showCheckout = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(OnboardColor.text)
                .padding(.top, Spacing.xl)

            VStack(spacing: 6) {
                Text("One-time onboarding fee")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(OnboardColor.text)
                Text("₹\(amountINR)")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(OnboardColor.text)
                Text("Paid once, before your application is sent for verification.")
                    .font(.system(size: 14))
                    .foregroundStyle(OnboardColor.subtle)
                    .multilineTextAlignment(.center)
            }

            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isError ? Color(hex: 0xDC2626) : OnboardColor.subtle)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            OnboardPrimaryButton(
                title: phase == .notYet ? "Check Again" : "Pay ₹\(amountINR)",
                busyTitle: phase == .checking ? "Checking payment..." : "Opening payment...",
                isBusy: phase == .opening || phase == .checking,
                isEnabled: true
            ) {
                Task { phase == .notYet ? await check() : await pay() }
            }

            if phase == .notYet {
                Button("Open the payment page again") { Task { await pay() } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OnboardColor.text)
            }

            Button("Not now") { dismiss() }
                .font(.system(size: 14))
                .foregroundStyle(OnboardColor.subtle)
                .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.xl)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(phase == .opening || phase == .checking)
        .fullScreenCover(isPresented: $showCheckout) {
            if let url = link?.url {
                SafariCheckoutView(url: url) {
                    showCheckout = false
                    Task { await check() }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var message: String? {
        switch phase {
        case .notYet: "We haven't received the payment yet. If you've paid, give it a moment and check again."
        case .failed(let text): text
        default: nil
        }
    }

    private var isError: Bool { if case .failed = phase { true } else { false } }

    private func pay() async {
        phase = .opening
        do {
            let created = try await OnboardingFeeAPI.createLink()
            if created.paid == true {
                finish()
                return
            }
            guard created.url != nil else { throw OnboardingFeeAPI.FeeError(message: "Couldn't open the payment page.") }
            link = created
            phase = .ready
            showCheckout = true
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Razorpay can take a few seconds to mark the link paid after the page
    /// says so; ask a few times before calling it unpaid.
    private func check() async {
        guard let linkID = link?.linkID else { phase = .ready; return }
        phase = .checking
        for attempt in 0..<4 {
            if (try? await OnboardingFeeAPI.confirm(linkID: linkID)) == true {
                finish()
                return
            }
            if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
        }
        phase = .notYet
    }

    private func finish() {
        dismiss()
        onPaid()
    }
}
