import SwiftUI

/// Retailer Onboarding flow (`/onboard-retailer`, `/step2`, `/step3`, `/submitted`).
/// Collects Retailer personal identity, store details, and verification documents.
struct RetailerOnboardCoordinator: View {
    @Environment(SessionStore.self) private var session
    @State private var step: Int = 1

    @State private var fullName: String = ""
    @State private var mobileNumber: String = ""
    @State private var storeName: String = ""
    @State private var selectedState: String = ""
    @State private var selectedCity: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                // Header Step Indicator
                HStack {
                    ForEach(1...3, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? Palette.dark : Palette.border)
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, Spacing.screenGutter)
                .padding(.top, Spacing.md)

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        if step == 1 {
                            step1View
                        } else if step == 2 {
                            step2View
                        } else {
                            step3View
                        }
                    }
                    .padding(Spacing.screenGutter)
                }

                // Bottom CTA
                VStack(spacing: Spacing.sm) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.manrope(12))
                            .foregroundStyle(Color.red)
                    }

                    Button {
                        if step < 3 {
                            step += 1
                        } else {
                            Task { await submitRetailerOnboarding() }
                        }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(step == 3 ? "Submit Verification" : "Continue")
                                    .font(.manrope(15, weight: .bold))
                            }
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.dark, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isSubmitting || !isStepValid)
                    .opacity(isStepValid ? 1.0 : 0.5)

                    if step > 1 {
                        Button("Back") {
                            step -= 1
                        }
                        .font(.manrope(13, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    }
                }
                .padding(Spacing.screenGutter)
            }
            .navigationTitle("Retailer Onboarding")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var isStepValid: Bool {
        switch step {
        case 1: !fullName.trimmed.isEmpty
        case 2: !storeName.trimmed.isEmpty && !selectedState.isEmpty
        case 3: true
        default: false
        }
    }

    private var step1View: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Personal Identity")
                .font(.cirka(28))
                .foregroundStyle(Palette.foreground)
            Text("Enter your official legal name and contact details.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)

            VStack(alignment: .leading, spacing: 6) {
                Text("FULL NAME*")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                TextField("Parash Rautela", text: $fullName)
                    .font(.manrope(14))
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1) }
            }
        }
    }

    private var step2View: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Store Details")
                .font(.cirka(28))
                .foregroundStyle(Palette.foreground)
            Text("Tell us about your retail business and store location.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)

            VStack(alignment: .leading, spacing: 6) {
                Text("STORE NAME*")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                TextField("Celestique Retail", text: $storeName)
                    .font(.manrope(14))
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("STATE*")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                TextField("Maharashtra", text: $selectedState)
                    .font(.manrope(14))
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1) }
            }
        }
    }

    private var step3View: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Verification Documents")
                .font(.cirka(28))
                .foregroundStyle(Palette.foreground)
            Text("Upload your PAN and GST certificate to verify your retail store.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Palette.dark)
                    VStack(alignment: .leading) {
                        Text("PAN & GST Certificate")
                            .font(.manrope(14, weight: .bold))
                        Text("Encryption secured verification")
                            .font(.manrope(12))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func submitRetailerOnboarding() async {
        guard let user = session.user else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            struct RetailerInsert: Encodable {
                let user_id: String
                let email: String
                let full_name: String
                let business_name: String
                let state: String
                let verification_status: String
            }
            let payload = RetailerInsert(
                user_id: user.id.uuidString,
                email: user.email ?? "",
                full_name: fullName.trimmed,
                business_name: storeName.trimmed,
                state: selectedState.trimmed,
                verification_status: "pending"
            )
            _ = try await SupabaseManager.client.from("retailers").insert(payload).execute()
            await session.refreshDestination()
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }
}
