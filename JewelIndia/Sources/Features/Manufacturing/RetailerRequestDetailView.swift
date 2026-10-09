import SwiftUI

public struct RetailerRequestDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let requestID: UUID

    @State private var request: ManufacturingRequest?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var showCancelConfirm: Bool = false
    @State private var isCancelling: Bool = false
    @State private var showResubmitSheet: Bool = false
    @State private var selectedQuote: ManufacturingQuote?
    @State private var isAwarding = false
    @State private var awardError: String?
    @State private var quoteSort = "making"
    @Environment(\.scenePhase) private var scenePhase

    public init(requestID: UUID) {
        self.requestID = requestID
    }

    public var body: some View {
        ZStack {
            Palette.cream.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading enquiry…")
            } else if let request {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        statusBanner(request)
                        photoSection(request)
                        if request.parsedState == .assigned, let quote = request.quote {
                            quoteCard(quote, wholesaler: request.assignedWholesaler)
                        }
                        if request.broadcastMode == "parallel", request.parsedState != .assigned {
                            comparisonSection(request)
                        }
                        specificationsCard(request)
                        actionsSection(request)
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
        .navigationTitle("Enquiry Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
                if scenePhase == .active && !isAwarding && !showCancelConfirm {
                    if let latest = try? await ManufacturingAPI.fetchRetailerRequestDetail(id: requestID) { request = latest }
                }
            }
        }
        .refreshable {
            await loadDetail()
        }
        .confirmationDialog(
            "Cancel Manufacturing Request?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel Request", role: .destructive) {
                Task { await cancelRequest() }
            }
            Button("Keep Active", role: .cancel) {}
        } message: {
            Text("This will close the enquiry and all open supplier invitations. You will no longer be able to select a quote.")
        }
        .confirmationDialog("Select This Supplier?", isPresented: Binding(
            get: { selectedQuote != nil }, set: { if !$0 { selectedQuote = nil } }
        ), titleVisibility: .visible) {
            if let quote = selectedQuote {
                Button("Confirm Supplier Selection") { Task { await award(quote) } }
            }
            Button("Keep Comparing", role: .cancel) { selectedQuote = nil }
        } message: {
            Text("This awards the project to the selected supplier and closes the enquiry for all other wholesalers.")
        }
        .alert("Could Not Complete Action", isPresented: Binding(
            get: { awardError != nil }, set: { if !$0 { awardError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(awardError ?? "") }
        .sheet(isPresented: $showResubmitSheet) {
            if let request {
                CreateManufacturingRequestSheet(
                    initialCategory: request.category,
                    onCreated: { _ in
                        dismiss()
                    }
                )
            }
        }
    }

    // MARK: - Status Banner

    private func statusBanner(_ req: ManufacturingRequest) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: statusIcon(req.parsedState))
                .font(.system(size: 24))
                .foregroundStyle(statusColor(req.parsedState))

            VStack(alignment: .leading, spacing: 2) {
                Text(req.parsedState.title)
                    .font(.manrope(15, weight: .semibold))
                    .foregroundStyle(Palette.dark)

                Text(statusDescription(req.parsedState))
                    .font(.manrope(12, weight: .regular))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor(req.parsedState).opacity(0.3), lineWidth: 1)
        )
    }

    private func statusIcon(_ state: ManufacturingRequestState) -> String {
        switch state {
        case .collecting: "person.3.fill"
        case .reviewing: "list.bullet.rectangle"
        case .routing: "hourglass.circle.fill"
        case .assigned: "checkmark.seal.fill"
        case .exhausted: "xmark.circle.fill"
        case .cancelled: "slash.circle.fill"
        }
    }

    private func statusColor(_ state: ManufacturingRequestState) -> Color {
        switch state {
        case .collecting, .reviewing, .routing: Palette.statusPending
        case .assigned: Palette.statusVerified
        case .exhausted: Palette.muted
        case .cancelled: Palette.statusRejected
        }
    }

    private func statusDescription(_ state: ManufacturingRequestState) -> String {
        switch state {
        case .collecting: "Wholesalers can quote together. Compare responses and select your supplier."
        case .reviewing: "The quotation deadline has passed. Choose from the quotes received."
        case .routing: "Being reviewed by verified wholesalers in 30-minute sequential turns."
        case .assigned: "The project is assigned to the selected supplier. Review the agreed quote below."
        case .exhausted: "No wholesalers accepted within requested constraints."
        case .cancelled: "This request was cancelled."
        }
    }

    // MARK: - Photo Section

    private func photoSection(_ req: ManufacturingRequest) -> some View {
        Group {
            if let imageURL = req.imageUrl, let url = URL(string: imageURL) {
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

    // MARK: - Quote Card

    private func quoteCard(_ quote: ManufacturingQuote, wholesaler: WholesalerBusinessSummary?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(request?.parsedState == .assigned ? "Selected Wholesaler Quote" : "Supplier Quote")
                    .font(.manrope(15, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                Spacer()
                Text(request?.parsedState == .assigned ? "SELECTED" : "ESTIMATE")
                    .font(.manrope(11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Palette.statusVerified.opacity(0.15))
                    .foregroundStyle(Palette.statusVerified)
                    .clipShape(Capsule())
            }

            if let ws = wholesaler {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "building.2.fill")
                        .foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ws.businessName ?? "Verified Wholesaler")
                            .font(.manrope(14, weight: .semibold))
                            .foregroundStyle(Palette.dark)
                        if let city = ws.city, let state = ws.state {
                            Text("\(city), \(state)")
                                .font(.manrope(12, weight: .regular))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
                .padding(.bottom, 4)
            }

            Divider()

            VStack(spacing: 8) {
                detailRow(label: "Making Charge", value: quote.formattedMakingCharge)
                if let metal = quote.metalEstimateAmount, metal > 0 {
                    detailRow(label: "Estimated Metal Total", value: String(format: "₹%.0f", metal))
                }
                if let stones = quote.gemstoneEstimateAmount, stones > 0 {
                    detailRow(label: "Estimated Stones Total", value: String(format: "₹%.0f", stones))
                }
                if let other = quote.otherEstimateAmount, other > 0 {
                    detailRow(label: "Other Costs", value: String(format: "₹%.0f", other))
                }
                detailRow(label: "Proposed Delivery", value: quote.proposedDeliveryDate)
                if let request { detailRow(label: "Estimated Total", value: estimatedTotal(quote, request)) }
            }

            if let comments = quote.comments, !comments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Supplier Notes")
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                    Text(comments)
                        .font(.manrope(13, weight: .regular))
                        .foregroundStyle(Palette.dark)
                }
                .padding(10)
                .background(Palette.cream)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(Spacing.base)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Palette.statusVerified.opacity(0.3), lineWidth: 1)
        )
    }

    private func comparisonSection(_ req: ManufacturingRequest) -> some View {
        let quotes = (req.quotes ?? []).sorted {
            if quoteSort == "delivery" { return $0.proposedDeliveryDate < $1.proposedDeliveryDate }
            return $0.makingChargeAmount < $1.makingChargeAmount
        }
        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Compare Supplier Quotes (\(quotes.count))")
                .font(.manrope(17, weight: .semibold))
            if let deadline = req.quotationDeadline {
                Text("Quotes close: \(displayDeadline(deadline))")
                    .font(.manrope(12, weight: .regular)).foregroundStyle(Palette.muted)
            }
            Text("Estimates use the requested quantity and entered supplier costs; unlisted costs and taxes are excluded. Weight changes may change per-gram totals. Review supplier notes before selecting.")
                .font(.manrope(12, weight: .regular)).foregroundStyle(Palette.muted)
            if quotes.isEmpty {
                Text(req.parsedState == .collecting ? "No quotes yet. Supplier responses will appear here." : "No quotes were received.")
                    .padding(Spacing.base)
            } else {
                Picker("Compare By", selection: $quoteSort) {
                    Text("Making Charge").tag("making")
                    Text("Delivery Date").tag("delivery")
                }.pickerStyle(.segmented)
                ForEach(quotes) { quote in
                    VStack(spacing: Spacing.sm) {
                        quoteCard(quote, wholesaler: quote.wholesaler)
                        if [.collecting, .reviewing].contains(req.parsedState) {
                            Button {
                                selectedQuote = quote
                            } label: {
                                Text(isAwarding ? "Selecting Supplier…" : "Select This Supplier")
                                    .font(.manrope(15, weight: .semibold)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(Palette.dark).clipShape(RoundedRectangle(cornerRadius: 12))
                            }.disabled(isAwarding || isCancelling)
                        }
                    }
                }
            }
        }
    }

    private func displayDeadline(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        return date?.formatted(date: .abbreviated, time: .shortened) ?? raw
    }

    private func estimatedTotal(_ quote: ManufacturingQuote, _ req: ManufacturingRequest) -> String {
        let base = (quote.metalEstimateAmount ?? 0) + (quote.gemstoneEstimateAmount ?? 0) + (quote.otherEstimateAmount ?? 0)
        switch quote.parsedMode {
        case .fixedTotal:
            return String(format: "₹%.0f", base + quote.makingChargeAmount)
        case .percentage:
            return String(format: "₹%.0f", base + (quote.metalEstimateAmount ?? 0) * quote.makingChargeAmount / 100)
        case .perGram:
            let low = base + quote.makingChargeAmount * req.minWeightGrams * Double(req.quantity)
            let high = base + quote.makingChargeAmount * req.maxWeightGrams * Double(req.quantity)
            return String(format: "₹%.0f – ₹%.0f", low, high)
        }
    }

    private func award(_ quote: ManufacturingQuote) async {
        isAwarding = true
        do {
            try await ManufacturingAPI.awardQuote(requestID: requestID, quoteID: quote.id)
            selectedQuote = nil
            await loadDetail()
        } catch {
            awardError = error.localizedDescription
            if let latest = try? await ManufacturingAPI.fetchRetailerRequestDetail(id: requestID) { request = latest }
        }
        isAwarding = false
    }

    // MARK: - Specifications Card

    private func specificationsCard(_ req: ManufacturingRequest) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Specifications")
                .font(.manrope(15, weight: .semibold))
                .foregroundStyle(Palette.dark)

            VStack(spacing: 8) {
                detailRow(label: "Category", value: req.category)
                detailRow(label: "Expected Weight", value: req.formattedWeightRange)
                detailRow(label: "Material & Purity", value: "\(req.material) (\(req.purity))")
                detailRow(label: "Gemstone Preference", value: req.gemstonePreference)
                detailRow(label: "Quantity", value: "\(req.quantity) pc")
                detailRow(label: "Max Making Budget", value: req.formattedBudget)
                detailRow(label: "Target Delivery", value: req.deliveryNeededDate)
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

    // MARK: - Actions

    private func actionsSection(_ req: ManufacturingRequest) -> some View {
        VStack(spacing: Spacing.md) {
            if [.routing, .collecting, .reviewing].contains(req.parsedState) {
                Button(role: .destructive) {
                    showCancelConfirm = true
                } label: {
                    Text("Cancel Request")
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
                .disabled(isCancelling || isAwarding)
            } else if req.parsedState == .exhausted {
                Button {
                    showResubmitSheet = true
                } label: {
                    Text("Revise & Resubmit Enquiry")
                        .font(.manrope(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.dark)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            request = try await ManufacturingAPI.fetchRetailerRequestDetail(id: requestID)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func cancelRequest() async {
        isCancelling = true
        do {
            try await ManufacturingAPI.cancelRequest(id: requestID)
            isCancelling = false
            await loadDetail()
        } catch {
            isCancelling = false
            awardError = error.localizedDescription
        }
    }
}
