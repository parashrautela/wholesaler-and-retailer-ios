import SwiftUI

public struct WholesalerOfferDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let offerID: UUID
    var onActionCompleted: (() -> Void)?

    @State private var offer: ManufacturingOffer?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var showAcceptSheet: Bool = false
    @State private var showDeclineSheet: Bool = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(offerID: UUID, onActionCompleted: (() -> Void)? = nil) {
        self.offerID = offerID
        self.onActionCompleted = onActionCompleted
    }

    public var body: some View {
        ZStack {
            Palette.cream.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading offer…")
            } else if let offer {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        if offer.isActive {
                            activeCountdownBanner(offer)
                        } else {
                            statusBanner(offer.parsedStatus)
                        }

                        photoSection(offer)
                        specificationsSection(offer)

                        if offer.isActive {
                            actionButtons
                        } else if let quote = offer.quote {
                            acceptedQuoteCard(quote)
                        }
                    }
                    .padding(Spacing.base)
                }
            } else if let errorMessage {
                VStack(spacing: Spacing.md) {
                    Text(errorMessage)
                        .font(.manrope(14, weight: .medium))
                        .foregroundStyle(Palette.statusRejected)
                    Button("Try Again") {
                        Task { await loadDetail() }
                    }
                }
            }
        }
        .navigationTitle("Offer Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
        }
        .refreshable {
            await loadDetail()
        }
        .onReceive(timer) { _ in
            if var current = offer, current.remainingSeconds > 0 {
                current.remainingSeconds -= 1
                offer = current
            }
        }
        .sheet(isPresented: $showAcceptSheet) {
            if let offer {
                AcceptQuoteSheet(offer: offer, onAccepted: {
                    onActionCompleted?()
                    Task { await loadDetail() }
                })
            }
        }
        .sheet(isPresented: $showDeclineSheet) {
            DeclineOfferSheet(offerID: offerID, onDeclined: {
                onActionCompleted?()
                dismiss()
            })
        }
    }

    // MARK: - Countdown & Status Banners

    private func activeCountdownBanner(_ off: ManufacturingOffer) -> some View {
        let hours = off.remainingSeconds / 3600
        let mins = (off.remainingSeconds % 3600) / 60
        let secs = off.remainingSeconds % 60

        return HStack(spacing: Spacing.md) {
            Image(systemName: "timer")
                .font(.system(size: 24))
                .foregroundStyle(Palette.statusPending)

            VStack(alignment: .leading, spacing: 2) {
                Text(off.request?.broadcastMode == "parallel" ? "Shared Quotation Deadline" : "Exclusive 30-Minute Turn")
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                Text(off.request?.broadcastMode == "parallel" ? "Submit a quote. The retailer selects the supplier." : "This enquiry is reserved for you right now.")
                    .font(.manrope(11, weight: .regular))
                    .foregroundStyle(Palette.muted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%02d:%02d:%02d", hours, mins, secs))
                    .font(.manrope(18, weight: .bold))
                    .foregroundStyle(Palette.statusPending)
                Text("remaining")
                    .font(.manrope(10, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Palette.statusPending.opacity(0.4), lineWidth: 1)
        )
    }

    private func statusBanner(_ status: ManufacturingOfferStatus) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: status == .accepted ? "checkmark.circle.fill" : status == .quoted ? "hourglass.circle" : "clock.badge.xmark")
                .font(.system(size: 24))
                .foregroundStyle(status == .accepted ? Palette.statusVerified : Palette.muted)

            VStack(alignment: .leading, spacing: 2) {
                Text("Offer \(status.title)")
                    .font(.manrope(15, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                Text(status == .quoted ? "Your quote is awaiting the retailer’s selection." : status == .accepted ? "This project is assigned to you." : "This enquiry is no longer open for your response.")
                    .font(.manrope(12, weight: .regular))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Photo Section

    private func photoSection(_ off: ManufacturingOffer) -> some View {
        Group {
            if let imageURL = off.imageUrl, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 280)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .background(Palette.taupe.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    // MARK: - Specifications Section

    private func specificationsSection(_ off: ManufacturingOffer) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Requirements")
                .font(.manrope(15, weight: .semibold))
                .foregroundStyle(Palette.dark)

            if let req = off.request {
                VStack(spacing: 8) {
                    detailRow(label: "Category", value: req.category)
                    detailRow(label: "Expected Weight", value: req.formattedWeightRange)
                    detailRow(label: "Material & Purity", value: "\(req.material) (\(req.purity))")
                    detailRow(label: "Gemstone Preference", value: req.gemstonePreference)
                    detailRow(label: "Quantity", value: "\(req.quantity) pc")
                    detailRow(label: "Retailer's Max Budget", value: req.formattedBudget)
                    detailRow(label: "Delivery Deadline", value: req.deliveryNeededDate)
                }

                if let notes = req.notes, !notes.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Retailer Design Notes")
                            .font(.manrope(12, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                        Text(notes)
                            .font(.manrope(13, weight: .regular))
                            .foregroundStyle(Palette.dark)
                    }
                }
            }
        }
        .padding(Spacing.base)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.manrope(13, weight: .regular))
                .foregroundStyle(Palette.muted)
            Spacer()
            Text(value)
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: Spacing.md) {
            Button {
                showAcceptSheet = true
            } label: {
                Text(offer?.request?.broadcastMode == "parallel" ? "Submit Quote" : "Accept with Quote")
                    .font(.manrope(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.dark)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                showDeclineSheet = true
            } label: {
                Text("Decline Offer")
                    .font(.manrope(15, weight: .semibold))
                    .foregroundStyle(Palette.statusRejected)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Palette.statusRejected.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Accepted Quote Card

    private func acceptedQuoteCard(_ quote: ManufacturingQuote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Submitted Quote")
                .font(.manrope(15, weight: .semibold))
                .foregroundStyle(Palette.dark)

            detailRow(label: "Making Charge", value: quote.formattedMakingCharge)
            if let metal = quote.metalEstimateAmount, metal > 0 {
                detailRow(label: "Metal Estimate", value: String(format: "₹%.0f", metal))
            }
            if let stones = quote.gemstoneEstimateAmount, stones > 0 {
                detailRow(label: "Stones Estimate", value: String(format: "₹%.0f", stones))
            }
            detailRow(label: "Committed Delivery", value: quote.proposedDeliveryDate)
            if let comments = quote.comments, !comments.isEmpty {
                Text("Terms: \(comments)")
                    .font(.manrope(12, weight: .regular))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 4)
            }
        }
        .padding(Spacing.base)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            offer = try await ManufacturingAPI.fetchWholesalerOfferDetail(id: offerID)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
