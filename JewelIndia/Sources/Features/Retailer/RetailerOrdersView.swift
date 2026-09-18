import SwiftUI

/// Retailer-owned order history. Supplier identity is visible here because an
/// order has already been placed; it remains absent from the Discover feed.
struct RetailerOrdersView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"

        var id: String { rawValue }
    }

    @State private var selectedFilter: Filter = .all
    @State private var response: JewelAPI.RetailerOrdersResponse?
    @State private var isLoading = true
    @State private var error: String?

    private var orders: [Order] {
        let all = response?.orders ?? []
        switch selectedFilter {
        case .all:
            return all
        case .active:
            return all.filter {
                [.pending, .accepted, .inProduction, .packed, .dispatched].contains($0.status)
            }
        case .completed:
            return all.filter { [.received, .completed, .rejected].contains($0.status) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Order status", selection: $selectedFilter) {
                ForEach(Filter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(Spacing.base)

            Group {
                if isLoading && response == nil {
                    ProgressView("Loading orders…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, response == nil {
                    ContentUnavailableView {
                        Label("Couldn’t load orders", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                } else if orders.isEmpty {
                    ContentUnavailableView(
                        "No \(selectedFilter.rawValue.lowercased()) orders",
                        systemImage: "bag",
                        description: Text("Your jewellery requests will appear here.")
                    )
                } else {
                    List(orders) { order in
                        orderRow(order)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .refreshTask { await load() }
                }
            }
        }
        .background(Palette.background)
        .navigationTitle("Orders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func orderRow(_ order: Order) -> some View {
        let product = order.productId.flatMap { response?.products[$0] }
        let supplier = order.wholesalerId.flatMap { response?.suppliers[$0] }

        return HStack(alignment: .top, spacing: Spacing.md) {
            ZStack {
                Palette.background
                if let url = product?.displayImageURL(.card) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { ProgressView() }
                } else {
                    Image(systemName: "photo").foregroundStyle(Palette.muted)
                }
            }
            .frame(width: 76, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(product?.title?.trimmed.nilIfEmpty ?? product?.jewelleryType?.capitalized ?? "Jewellery request")
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(Palette.foreground)
                        .lineLimit(2)
                    Spacer(minLength: Spacing.sm)
                    if let status = order.status { OrderStatusBadge(status: status) }
                }

                if let supplier {
                    Text("Supplier: \(supplier.displayName)")
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(Palette.foreground)
                }

                Text("Order #\(order.id.prefix(8))")
                    .font(.manrope(11))
                    .foregroundStyle(Palette.muted)

                if let note = order.customizationNote?.trimmed.nilIfEmpty {
                    Text(note)
                        .font(.manrope(11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            response = try await JewelAPI.fetchRetailerOrders()
        } catch {
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }
}
