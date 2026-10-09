import SwiftUI

public struct DeclineOfferSheet: View {
    @Environment(\.dismiss) private var dismiss

    let offerID: UUID
    var onDeclined: (() -> Void)?

    @State private var selectedReasonIndex: Int = 0
    @State private var customReason: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @State private var idempotencyKey: String = UUID().uuidString

    private let commonReasons = [
        "Manufacturing capacity currently full",
        "Delivery timeline is too tight",
        "Raw materials or gemstones unavailable",
        "Budget constraints not viable",
        "Other reason"
    ]

    public init(offerID: UUID, onDeclined: (() -> Void)? = nil) {
        self.offerID = offerID
        self.onDeclined = onDeclined
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Palette.cream.ignoresSafeArea()

                VStack(spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reason for Declining (Optional)")
                            .font(.manrope(15, weight: .semibold))
                            .foregroundStyle(Palette.dark)
                        Text("Your feedback is optional and will not be visible to competing suppliers.")
                            .font(.manrope(12, weight: .regular))
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 8) {
                        ForEach(commonReasons.indices, id: \.self) { idx in
                            Button {
                                selectedReasonIndex = idx
                            } label: {
                                HStack {
                                    Text(commonReasons[idx])
                                        .font(.manrope(14, weight: .regular))
                                        .foregroundStyle(Palette.dark)
                                    Spacer()
                                    Image(systemName: selectedReasonIndex == idx ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedReasonIndex == idx ? Palette.dark : Palette.border)
                                }
                                .padding(12)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if selectedReasonIndex == commonReasons.count - 1 {
                        TextField("Specify reason (optional)…", text: $customReason, axis: .vertical)
                            .lineLimit(3...4)
                            .padding(10)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Spacer()

                    Button(role: .destructive) {
                        Task { await submitDecline() }
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Confirm Decline")
                                .font(.manrope(15, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.statusRejected)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isSubmitting)
                }
                .padding(Spacing.base)
            }
            .navigationTitle("Decline Offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.manrope(15, weight: .regular))
                        .foregroundStyle(Palette.dark)
                }
            }
            .alert("Decline Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func submitDecline() async {
        isSubmitting = true
        errorMessage = nil

        let reason: String = {
            if selectedReasonIndex == commonReasons.count - 1 {
                return customReason.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return commonReasons[selectedReasonIndex]
        }()

        do {
            try await ManufacturingAPI.declineOffer(
                id: offerID,
                reason: reason.isEmpty ? nil : reason,
                idempotencyKey: idempotencyKey
            )
            isSubmitting = false
            onDeclined?()
            dismiss()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
        }
    }
}
