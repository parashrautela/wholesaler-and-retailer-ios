import SwiftUI

public struct AcceptQuoteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let offer: ManufacturingOffer
    var onAccepted: (() -> Void)?

    @State private var makingChargeText: String = ""
    @State private var metalEstimateText: String = ""
    @State private var gemstoneEstimateText: String = ""
    @State private var otherEstimateText: String = ""
    @State private var proposedDeliveryDate: Date = Date()
    @State private var comments: String = ""

    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @State private var idempotencyKey: String = UUID().uuidString

    public init(offer: ManufacturingOffer, onAccepted: (() -> Void)? = nil) {
        self.offer = offer
        self.onAccepted = onAccepted
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Palette.cream.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        constraintHeader

                        VStack(spacing: Spacing.md) {
                            makingChargeInput
                            estimateInputs
                            deliveryDateInput
                            commentsInput
                        }
                        .padding(Spacing.base)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        Button {
                            Task { await submitAcceptance() }
                        } label: {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(offer.request?.broadcastMode == "parallel" ? "Submit Quote" : "Accept Enquiry with Quote")
                                    .font(.manrope(15, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.dark)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(isSubmitting)
                    }
                    .padding(Spacing.base)
                }
            }
            .navigationTitle("Submit Commercial Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.manrope(15, weight: .regular))
                        .foregroundStyle(Palette.dark)
                }
            }
            .onAppear {
                if let req = offer.request {
                    makingChargeText = String(format: "%.0f", req.makingBudgetAmount)
                    let dates = DateFormatter()
                    dates.dateFormat = "yyyy-MM-dd"
                    if let d = dates.date(from: req.deliveryNeededDate) {
                        proposedDeliveryDate = d
                    }
                }
            }
            .alert("Quote Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var constraintHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Retailer's Maximum Constraints")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)

            if let req = offer.request {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Max Making Budget")
                            .font(.manrope(11, weight: .regular))
                            .foregroundStyle(Palette.muted)
                        Text(req.formattedBudget)
                            .font(.manrope(14, weight: .bold))
                            .foregroundStyle(Palette.dark)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Required By")
                            .font(.manrope(11, weight: .regular))
                            .foregroundStyle(Palette.muted)
                        Text(req.deliveryNeededDate)
                            .font(.manrope(14, weight: .bold))
                            .foregroundStyle(Palette.dark)
                    }
                }
                .padding(Spacing.md)
                .background(Palette.taupe.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var makingChargeInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quoted Making Charge (\(offer.request?.parsedBudgetMode.unitLabel ?? "₹"))")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)

            TextField("Amount", text: $makingChargeText)
                .keyboardType(.decimalPad)
                .padding(10)
                .background(Palette.cream)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if let req = offer.request, let entered = Double(makingChargeText), entered > req.makingBudgetAmount {
                Text("Warning: Quote cannot exceed requested budget (\(req.formattedBudget)).")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Palette.statusRejected)
            }
        }
    }

    private var estimateInputs: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimates for the Entire Quantity (₹)")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)

            Text("These are estimates, not a final invoice. The retailer chooses whether to award your quote.")
                .font(.manrope(12, weight: .regular)).foregroundStyle(Palette.muted)
            TextField("Other costs (₹)", text: $otherEstimateText)
                .keyboardType(.decimalPad).padding(10).background(Palette.cream)
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Metal (₹)").font(.manrope(11, weight: .regular)).foregroundStyle(Palette.muted)
                    TextField("Metal estimate", text: $metalEstimateText)
                        .keyboardType(.decimalPad)
                        .padding(10)
                        .background(Palette.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stones (₹)").font(.manrope(11, weight: .regular)).foregroundStyle(Palette.muted)
                    TextField("Stone estimate", text: $gemstoneEstimateText)
                        .keyboardType(.decimalPad)
                        .padding(10)
                        .background(Palette.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var deliveryDateInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Committed Delivery Date")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)

            DatePicker(
                "Delivery Date",
                selection: $proposedDeliveryDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .padding(8)
            .background(Palette.cream)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var commentsInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Manufacturing Notes / Terms")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)

            TextField("Tolerance, hallmark details, packaging…", text: $comments, axis: .vertical)
                .lineLimit(3...4)
                .padding(10)
                .background(Palette.cream)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func submitAcceptance() async {
        guard let req = offer.request else { return }
        guard let mc = Double(makingChargeText), mc > 0 else {
            errorMessage = "Please enter a valid making charge amount."
            return
        }

        if mc > req.makingBudgetAmount {
            errorMessage = "Making charge quote cannot exceed requested budget constraint."
            return
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: proposedDeliveryDate)

        if dateStr > req.deliveryNeededDate || proposedDeliveryDate < Calendar.current.startOfDay(for: Date()) {
            errorMessage = "Proposed delivery date cannot be later than requested deadline."
            return
        }

        for text in [metalEstimateText, gemstoneEstimateText, otherEstimateText] where !text.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let amount = Double(text), amount.isFinite, amount >= 0 else {
                errorMessage = "Estimates must be valid, nonnegative amounts."
                return
            }
        }
        if req.parsedBudgetMode == .percentage && (Double(metalEstimateText) ?? 0) <= 0 {
            errorMessage = "Enter the metal estimate used to calculate percentage making charges."
            return
        }
        isSubmitting = true
        errorMessage = nil

        do {
            let params = AcceptOfferQuoteParams(
                makingChargeMode: req.makingBudgetMode,
                makingChargeAmount: mc,
                metalEstimateAmount: Double(metalEstimateText),
                gemstoneEstimateAmount: Double(gemstoneEstimateText),
                otherEstimateAmount: Double(otherEstimateText),
                proposedDeliveryDate: dateStr,
                comments: comments.isEmpty ? nil : comments,
                expectedVersion: nil
            )

            try await ManufacturingAPI.acceptOffer(
                id: offer.id,
                params: params,
                parallel: req.broadcastMode == "parallel",
                idempotencyKey: idempotencyKey
            )

            isSubmitting = false
            onAccepted?()
            dismiss()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
        }
    }
}
