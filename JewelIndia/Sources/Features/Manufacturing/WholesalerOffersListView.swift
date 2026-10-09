import SwiftUI

public struct WholesalerOffersListView: View {
    @State private var offers: [ManufacturingOffer] = []
    @State private var isLoading: Bool = false
    @State private var selectedFilter: String? = nil
    @State private var selectedOffer: ManufacturingOffer?
    @State private var errorMessage: String?
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        ZStack {
            Palette.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar

                if isLoading && offers.isEmpty {
                    ProgressView("Loading offers…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if offers.isEmpty {
                    emptyState
                } else {
                    offersList
                }
            }
        }
        .navigationTitle("Manufacturing Offers")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadOffers()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
                if scenePhase == .active { await loadOffers() }
            }
        }
        .refreshable {
            await loadOffers()
        }
        .onReceive(timer) { _ in
            decrementTimers()
        }
        .navigationDestination(item: $selectedOffer) { off in
            WholesalerOfferDetailView(offerID: off.id, onActionCompleted: {
                Task { await loadOffers() }
            })
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(label: "Open for Quotes", status: "open")
                filterPill(label: "Quote Submitted", status: "quoted")
                filterPill(label: "Accepted", status: "accepted")
                filterPill(label: "Declined", status: "declined")
                filterPill(label: "Expired", status: "expired")
                filterPill(label: "Legacy Turns", status: "active")
                filterPill(label: "All", status: nil)
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.white)
    }

    private func filterPill(label: String, status: String?) -> some View {
        let isSelected = selectedFilter == status
        return Button {
            selectedFilter = status
            Task { await loadOffers() }
        } label: {
            Text(label)
                .font(.manrope(12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Palette.dark : Palette.cream)
                .foregroundStyle(isSelected ? .white : Palette.dark)
                .clipShape(Capsule())
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(Palette.muted)
            Text(selectedFilter == "active" ? "No Active Offers" : "No Offers Found")
                .font(.manrope(16, weight: .semibold))
                .foregroundStyle(Palette.dark)
            Text("Retailer enquiries are shared with verified wholesalers. Submit your quote before the deadline; the retailer chooses the supplier.")
                .font(.manrope(13, weight: .regular))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    private var offersList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                ForEach(offers) { offer in
                    Button {
                        selectedOffer = offer
                    } label: {
                        WholesalerOfferCard(offer: offer)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.base)
        }
    }

    private func decrementTimers() {
        for i in offers.indices {
            if offers[i].remainingSeconds > 0 {
                offers[i].remainingSeconds -= 1
            }
        }
    }

    private func loadOffers() async {
        isLoading = true
        errorMessage = nil
        do {
            offers = try await ManufacturingAPI.fetchWholesalerOffers(status: selectedFilter)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Wholesaler Offer Card

struct WholesalerOfferCard: View {
    let offer: ManufacturingOffer

    var body: some View {
        HStack(spacing: Spacing.md) {
            if let imageURL = offer.imageUrl, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Palette.taupe.opacity(0.5)
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Palette.taupe.opacity(0.4))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(Palette.muted)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(offer.request?.category ?? "Custom Jewellery")
                        .font(.manrope(15, weight: .semibold))
                        .foregroundStyle(Palette.dark)
                    Spacer()
                    if offer.isActive {
                        countdownBadge(offer.remainingSeconds)
                    } else {
                        statusPill(offer.parsedStatus)
                    }
                }

                if let req = offer.request {
                    Text("\(req.material) • \(req.formattedWeightRange)")
                        .font(.manrope(13, weight: .regular))
                        .foregroundStyle(Palette.muted)

                    HStack {
                        Text("Budget: \(req.formattedBudget)")
                            .font(.manrope(12, weight: .semibold))
                            .foregroundStyle(Palette.dark)
                        Spacer()
                        Text("Need by \(req.deliveryNeededDate)")
                            .font(.manrope(11, weight: .regular))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(offer.isActive ? Palette.statusPending.opacity(0.5) : Palette.border.opacity(0.5), lineWidth: 1)
        )
    }

    private func countdownBadge(_ seconds: Int) -> some View {
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        return HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 10))
            Text(String(format: "%02d:%02d:%02d", hours, mins, secs))
                .font(.manrope(11, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Palette.statusPending.opacity(0.15))
        .foregroundStyle(Palette.statusPending)
        .clipShape(Capsule())
    }

    private func statusPill(_ status: ManufacturingOfferStatus) -> some View {
        let (bg, fg, text): (Color, Color, String) = {
            switch status {
            case .open:
                return (Palette.statusPending.opacity(0.15), Palette.statusPending, "Open")
            case .quoted:
                return (Palette.statusPending.opacity(0.15), Palette.statusPending, "Quoted")
            case .notSelected:
                return (Palette.muted.opacity(0.15), Palette.muted, "Not Selected")
            case .active:
                return (Palette.statusPending.opacity(0.15), Palette.statusPending, "Active")
            case .accepted:
                return (Palette.statusVerified.opacity(0.15), Palette.statusVerified, "Accepted")
            case .declined:
                return (Palette.muted.opacity(0.15), Palette.muted, "Declined")
            case .expired:
                return (Palette.statusRejected.opacity(0.15), Palette.statusRejected, "Expired")
            case .cancelled:
                return (Palette.statusRejected.opacity(0.15), Palette.statusRejected, "Cancelled")
            case .skipped:
                return (Palette.muted.opacity(0.15), Palette.muted, "Skipped")
            }
        }()

        return Text(text)
            .font(.manrope(11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(Capsule())
    }
}
