import SwiftUI

public struct RetailerRequestsListView: View {
    @State private var requests: [ManufacturingRequest] = []
    @State private var isLoading: Bool = false
    @State private var selectedFilter: String? = nil
    @State private var showCreateSheet: Bool = false
    @State private var selectedRequest: ManufacturingRequest?
    @State private var errorMessage: String?

    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        ZStack {
            Palette.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar

                if isLoading && requests.isEmpty {
                    ProgressView("Loading enquiries…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if requests.isEmpty {
                    emptyState
                } else {
                    requestsList
                }
            }
        }
        .navigationTitle("Custom Enquiries")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.dark)
                }
            }
        }
        .task {
            await loadRequests()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
                if scenePhase == .active { await loadRequests() }
            }
        }
        .refreshable {
            await loadRequests()
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateManufacturingRequestSheet(onCreated: { newID in
                Task { await loadRequests() }
            })
        }
        .navigationDestination(item: $selectedRequest) { req in
            RetailerRequestDetailView(requestID: req.id)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(label: "All", status: nil)
                filterPill(label: "Collecting", status: "collecting")
                filterPill(label: "Compare Quotes", status: "reviewing")
                filterPill(label: "Quoted & Assigned", status: "assigned")
                filterPill(label: "Past / Exhausted", status: "exhausted")
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
            Task { await loadRequests() }
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
            Image(systemName: "hammer.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Palette.muted)
            Text("No Manufacturing Requests")
                .font(.manrope(16, weight: .semibold))
                .foregroundStyle(Palette.dark)
            Text("When you need a custom design made, broadcast your specifications to verified wholesalers.")
                .font(.manrope(13, weight: .regular))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Button {
                showCreateSheet = true
            } label: {
                Text("Create New Enquiry")
                    .font(.manrope(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Palette.dark)
                    .clipShape(Capsule())
            }
            .padding(.top, Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    private var requestsList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                ForEach(requests) { req in
                    Button {
                        selectedRequest = req
                    } label: {
                        RetailerRequestCard(request: req)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.base)
        }
    }

    private func loadRequests() async {
        isLoading = true
        errorMessage = nil
        do {
            requests = try await ManufacturingAPI.fetchRetailerRequests(status: selectedFilter)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Card Component

struct RetailerRequestCard: View {
    let request: ManufacturingRequest

    var body: some View {
        HStack(spacing: Spacing.md) {
            if let imageURL = request.imageUrl, let url = URL(string: imageURL) {
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
                    Text(request.category)
                        .font(.manrope(15, weight: .semibold))
                        .foregroundStyle(Palette.dark)
                    Spacer()
                    stateBadge(request.parsedState)
                }

                Text("\(request.material) • \(request.formattedWeightRange)")
                    .font(.manrope(13, weight: .regular))
                    .foregroundStyle(Palette.muted)

                HStack {
                    Text("Budget: \(request.formattedBudget)")
                        .font(.manrope(12, weight: .medium))
                        .foregroundStyle(Palette.dark)
                    Spacer()
                    if let wsName = request.assignedWholesalerName {
                        Text(wsName)
                            .font(.manrope(12, weight: .semibold))
                            .foregroundStyle(Palette.statusVerified)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Palette.border.opacity(0.5), lineWidth: 1)
        )
    }

    private func stateBadge(_ state: ManufacturingRequestState) -> some View {
        let (bg, fg, text): (Color, Color, String) = {
            switch state {
            case .collecting:
                return (Palette.statusPending.opacity(0.15), Palette.statusPending, "Collecting")
            case .reviewing:
                return (Palette.statusPending.opacity(0.15), Palette.statusPending, "Compare Quotes")
            case .routing:
                return (Palette.statusPending.opacity(0.15), Palette.statusPending, "Routing")
            case .assigned:
                return (Palette.statusVerified.opacity(0.15), Palette.statusVerified, "Assigned")
            case .exhausted:
                return (Palette.muted.opacity(0.15), Palette.muted, "No Suppliers")
            case .cancelled:
                return (Palette.statusRejected.opacity(0.15), Palette.statusRejected, "Cancelled")
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
