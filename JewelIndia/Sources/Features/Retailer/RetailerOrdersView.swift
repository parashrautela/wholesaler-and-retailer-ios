import SwiftUI
import Observation

/// Keeps retailer orders warm for the life of the signed-in shell. The order
/// list can therefore render immediately when its tab is selected, while a
/// pull-to-refresh still fetches the latest truth from the server.
@MainActor
@Observable
final class RetailerOrdersStore {
    private struct StaffName: Decodable {
        let id: String
        let full_name: String?
        let designation: String?
    }

    private(set) var response: JewelAPI.RetailerOrdersResponse?
    private(set) var isLoading = false
    private(set) var hasAttemptedLoad = false
    private(set) var errorMessage: String?
    private var staff: [String: StaffName] = [:]
    private var hasLoaded = false

    var showsInitialLoading: Bool {
        !hasAttemptedLoad || (isLoading && response == nil)
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        hasAttemptedLoad = true
        defer { isLoading = false }
        do {
            let fresh = try await JewelAPI.fetchRetailerOrders()
            response = fresh
            hasLoaded = true
            errorMessage = nil

            // Staff names enrich the cards, but they must never hold up the
            // whole Orders page. Render the order response first, then fill
            // these labels in as the small follow-up query completes.
            Task { [weak self] in
                await self?.loadStaff(for: fresh.orders)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func placedBy(_ order: Order) -> String {
        guard let id = order.employeeId else { return "Placed by you" }
        guard let person = staff[id.lowercased()], let name = person.full_name?.trimmed.nilIfEmpty else {
            return "Placed by your staff"
        }
        let role = person.designation?.trimmed.nilIfEmpty.map { " (\($0))" } ?? " (staff)"
        return "Placed by \(name)\(role)"
    }

    private func loadStaff(for orders: [Order]) async {
        let ids = Array(Set(orders.compactMap { $0.employeeId?.lowercased() }))
        guard !ids.isEmpty else {
            staff = [:]
            return
        }
        guard let rows: [StaffName] = try? await SupabaseManager.client.from("employees")
            .select("id, full_name, designation")
            .in("id", values: ids)
            .execute()
            .value
        else { return }
        staff = Dictionary(uniqueKeysWithValues: rows.map { ($0.id.lowercased(), $0) })
    }
}

/// Retailer-owned order history. Supplier identity is visible here because an
/// order has already been placed; it remains absent from the Discover feed.
struct RetailerOrdersView: View {
    @Environment(RetailerOrdersStore.self) private var store
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"

        var id: String { rawValue }
    }

    @State private var selectedFilter: Filter = .all
    @State private var updatingID: String?
    @State private var actionError: String?

    private var orders: [Order] {
        let all = store.response?.orders ?? []
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
                if store.showsInitialLoading {
                    ProgressView("Loading orders…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = store.errorMessage, store.response == nil {
                    ContentUnavailableView {
                        Label("Couldn’t load orders", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") { Task { await store.refresh() } }
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
                    .refreshTask { await store.refresh() }
                }
            }
        }
        .background(Palette.background)
        .navigationTitle("Orders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadIfNeeded() }
        .alert(actionError ?? "", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }

    private func orderRow(_ order: Order) -> some View {
        let product = order.productId.flatMap { store.response?.products[$0] }
        let supplier = order.wholesalerId.flatMap { store.response?.suppliers[$0] }

        return HStack(alignment: .top, spacing: Spacing.md) {
            ZStack {
                Palette.background
                if let url = product?.displayImageURL(.card) {
                    ProtectedImageView(url: url)
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

                // Who asked, and who it went to — the owner oversees what
                // their staff order.
                Label(store.placedBy(order), systemImage: order.employeeId == nil ? "person.crop.circle" : "person.badge.clock")
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(order.employeeId == nil ? Palette.foreground : Color(hex: 0x1D4ED8))
                    .lineLimit(1)

                if let supplier {
                    Label(supplierLine(supplier), systemImage: "shippingbox")
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(Palette.foreground)
                        .lineLimit(2)
                }

                Text("Order #\(order.id.prefix(8))" + (OrderTime.full(order.createdAt).map { " · \($0)" } ?? ""))
                    .font(.manrope(11))
                    .foregroundStyle(Palette.muted)

                if let note = order.customizationNote?.trimmed.nilIfEmpty {
                    Text(note)
                        .font(.manrope(11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(3)
                }

                if order.status == .rejected, let reason = order.rejectionReason?.trimmed.nilIfEmpty {
                    Text("Reason: \(reason)")
                        .font(.manrope(11))
                        .foregroundStyle(Color.red)
                        .lineLimit(3)
                }

                if let next = Self.storeStep(after: order.status) {
                    Button {
                        Task { await advance(order, to: next.status) }
                    } label: {
                        HStack(spacing: 6) {
                            if updatingID == order.id {
                                ProgressView().tint(.white).controlSize(.mini)
                            }
                            Text(next.label)
                                .font(.manrope(12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Palette.dark, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(updatingID != nil)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    /// The store's own steps; everything before dispatch is the wholesaler's.
    static func storeStep(after status: OrderStatus?) -> (status: OrderStatus, label: String)? {
        switch status {
        case .dispatched: (.received, "Mark as Received")
        case .received: (.completed, "Complete Order")
        default: nil
        }
    }

    private func advance(_ order: Order, to status: OrderStatus) async {
        guard updatingID == nil else { return }
        updatingID = order.id
        defer { updatingID = nil }
        do {
            try await OrdersAPI.setStatus(orderID: order.id, status: status)
        } catch {
            actionError = error.localizedDescription
        }
        // Either way, show what is true now.
        await store.refresh()
    }

    private func supplierLine(_ supplier: JewelAPI.SupplierSummary) -> String {
        let place = [supplier.city, supplier.state].compactMap { $0?.trimmed.nilIfEmpty }.joined(separator: ", ")
        return place.isEmpty ? "To \(supplier.displayName)" : "To \(supplier.displayName), \(place)"
    }

}
