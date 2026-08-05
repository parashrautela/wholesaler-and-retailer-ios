import SwiftUI

/// The Wholesaler Orders management screen (`/dashboard/wholesaler/orders`).
/// Divided into sub-tabs: New Orders, Active Orders, Completed, and Rejected.
/// Provides status transitions (Accept, Pack, Dispatch, Reject).
struct WholesalerOrdersView: View {
    @Environment(SessionStore.self) private var session

    enum OrderTab: String, CaseIterable, Identifiable {
        case new = "new"
        case active = "active"
        case completed = "completed"
        case rejected = "rejected"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .new: "New Orders"
            case .active: "Active Orders"
            case .completed: "Completed"
            case .rejected: "Rejected"
            }
        }
    }

    @State private var selectedTab: OrderTab = .new
    @State private var orders: [Order] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    // Order Action Confirmation Dialogs
    @State private var orderToAccept: Order? = nil
    @State private var orderToPack: Order? = nil
    @State private var orderToDispatch: Order? = nil
    @State private var orderToReject: Order? = nil
    @State private var rejectionReason: String = ""

    var filteredOrders: [Order] {
        orders.filter { order in
            guard let status = order.status else { return false }
            switch selectedTab {
            case .new:
                return status == .pending
            case .active:
                return status == .accepted || status == .inProduction || status == .packed || status == .dispatched
            case .completed:
                return status == .completed || status == .received
            case .rejected:
                return status == .rejected
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented Tab Picker
            Picker("Order Status", selection: $selectedTab) {
                ForEach(OrderTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(Spacing.screenGutter)
            .background(Palette.background)

            mainContent
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Orders")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadOrders()
        }
        .confirmationDialog(
            "Confirm Order?",
            isPresented: Binding(get: { orderToAccept != nil }, set: { if !$0 { orderToAccept = nil } }),
            titleVisibility: .visible
        ) {
            Button("Accept & Start Production") {
                if let order = orderToAccept {
                    Task { await updateStatus(order: order, status: .accepted) }
                }
            }
            Button("Cancel", role: .cancel) { orderToAccept = nil }
        } message: {
            Text("Are you sure you want to accept and start production for this order?")
        }
        .confirmationDialog(
            "Mark as Packed?",
            isPresented: Binding(get: { orderToPack != nil }, set: { if !$0 { orderToPack = nil } }),
            titleVisibility: .visible
        ) {
            Button("Confirm Packed") {
                if let order = orderToPack {
                    Task { await updateStatus(order: order, status: .packed) }
                }
            }
            Button("Cancel", role: .cancel) { orderToPack = nil }
        } message: {
            Text("Has this order been fully packed and prepared for shipping?")
        }
        .confirmationDialog(
            "Dispatch Order?",
            isPresented: Binding(get: { orderToDispatch != nil }, set: { if !$0 { orderToDispatch = nil } }),
            titleVisibility: .visible
        ) {
            Button("Confirm Dispatch") {
                if let order = orderToDispatch {
                    Task { await updateStatus(order: order, status: .dispatched) }
                }
            }
            Button("Cancel", role: .cancel) { orderToDispatch = nil }
        } message: {
            Text("Are you sure you want to mark this order as dispatched?")
        }
        .sheet(item: $orderToReject) { order in
            RejectOrderSheet(
                rejectionReason: $rejectionReason,
                onConfirm: {
                    Task { await updateStatus(order: order, status: .rejected, reason: rejectionReason) }
                },
                onCancel: { orderToReject = nil }
            )
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoading {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(Palette.dark)
            Spacer()
        } else if let errorMessage {
            Spacer()
            VStack(spacing: Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.red)
                Text(errorMessage)
                    .font(.manrope(14))
                    .foregroundStyle(Palette.muted)
                Button("Retry") {
                    Task { await loadOrders() }
                }
                .buttonStyle(.plain)
                .font(.manrope(14, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Palette.cream, in: Capsule())
            }
            Spacer()
        } else if filteredOrders.isEmpty {
            emptyStateView
        } else {
            List {
                ForEach(filteredOrders) { order in
                    OrderCardRow(
                        order: order,
                        onAccept: { orderToAccept = order },
                        onPack: { orderToPack = order },
                        onDispatch: { orderToDispatch = order },
                        onReject: { orderToReject = order }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await loadOrders()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(Palette.muted)
            Text("No \(selectedTab.title)")
                .font(.cirka(24))
                .foregroundStyle(Palette.foreground)
            Text("No orders match this status at the moment.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
            Spacer()
        }
    }

    private func loadOrders() async {
        guard let userId = session.user?.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            orders = try await WholesalerAPI.fetchOrders(wholesalerID: userId)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func updateStatus(order: Order, status: OrderStatus, reason: String? = nil) async {
        do {
            try await WholesalerAPI.updateOrderStatus(id: order.id, status: status, rejectionReason: reason)
            orderToAccept = nil
            orderToPack = nil
            orderToDispatch = nil
            orderToReject = nil
            rejectionReason = ""
            await loadOrders()
        } catch {
            errorMessage = "Failed to update status: \(error.localizedDescription)"
        }
    }
}

// MARK: - Reject Order Sheet

struct RejectOrderSheet: View {
    @Binding var rejectionReason: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                Text("Reject Order")
                    .font(.cirka(24))
                Text("Please specify why this order cannot be fulfilled.")
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)

                TextEditor(text: $rejectionReason)
                    .font(.manrope(14))
                    .frame(height: 120)
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))

                Spacer()

                Button(action: onConfirm) {
                    Text("Confirm Rejection")
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.xl)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Order Card Row

struct OrderCardRow: View {
    let order: Order
    let onAccept: () -> Void
    let onPack: () -> Void
    let onDispatch: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Order #\(order.id.prefix(8))")
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(Palette.foreground)

                Spacer()

                if let status = order.status {
                    OrderStatusBadge(status: status)
                }
            }

            if let note = order.customizationNote, !note.isEmpty {
                Text("Note: \(note)")
                    .font(.manrope(12))
                    .foregroundStyle(Palette.muted)
            }

            if let reason = order.rejectionReason, !reason.isEmpty {
                Text("Rejection Reason: \(reason)")
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(Color.red)
            }

            Divider()

            HStack(spacing: Spacing.sm) {
                if order.status == .pending {
                    Button(action: onAccept) {
                        Text("Accept")
                            .font(.manrope(12, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Palette.dark, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onReject) {
                        Text("Reject")
                            .font(.manrope(12, weight: .semibold))
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if order.status == .accepted || order.status == .inProduction {
                    Button(action: onPack) {
                        Text("Mark Packed")
                            .font(.manrope(12, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Palette.dark, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if order.status == .packed {
                    Button(action: onDispatch) {
                        Text("Dispatch Order")
                            .font(.manrope(12, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1) }
        .padding(.vertical, 4)
    }
}

// MARK: - Order Status Badge

struct OrderStatusBadge: View {
    let status: OrderStatus

    var body: some View {
        Text(status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.manrope(11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
            .foregroundStyle(textColor)
    }

    var backgroundColor: Color {
        switch status {
        case .pending: Color.orange.opacity(0.15)
        case .accepted, .inProduction: Color.blue.opacity(0.15)
        case .packed, .dispatched: Color.purple.opacity(0.15)
        case .received, .completed: Color.green.opacity(0.15)
        case .rejected: Color.red.opacity(0.15)
        }
    }

    var textColor: Color {
        switch status {
        case .pending: Color.orange
        case .accepted, .inProduction: Color.blue
        case .packed, .dispatched: Color.purple
        case .received, .completed: Color.green
        case .rejected: Color.red
        }
    }
}
