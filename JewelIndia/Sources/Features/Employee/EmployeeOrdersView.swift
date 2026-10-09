import SwiftUI

/// Staff Orders: the requests this staff member has sent, and where each one
/// has got to. For an owner in Employee View it is the whole store's — the
/// database's read rules decide, not this screen.
struct EmployeeOrdersView: View {
    @Environment(\.employeeAppearance) private var appearance
    @State private var updatingID: String?
    @State private var actionError: String?
    @Environment(EmployeeStore.self) private var store

    #if DEBUG
    /// Peeks only: rows to show instead of fetching.
    var peekOrders: [StaffOrder]?
    #endif

    var body: some View {
        Group {
            if store.showsInitialOrdersLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = store.ordersErrorMessage, store.staffOrders.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load orders", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await store.refreshOrders() } }
                }
            } else if store.staffOrders.isEmpty {
                ContentUnavailableView(
                    "No orders yet",
                    systemImage: "shippingbox",
                    description: Text("Requests you send from the catalogue will show up here.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        Text("Orders")
                            .font(appearance.cirka(30))
                            .foregroundStyle(appearance.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(store.staffOrders) { order in
                            row(order)
                        }
                    }
                    .padding(Spacing.screenGutter)
                    // The shell reserves its navigation; retain a small content gutter.
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(appearance.background.ignoresSafeArea())
        .task {
            #if DEBUG
            if let peekOrders {
                store.seedOrdersForPeek(peekOrders)
                return
            }
            #endif
            await store.loadOrdersIfNeeded()
        }
        .refreshTask { await store.refreshOrders() }
        .alert(actionError ?? "", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }

    private func row(_ order: StaffOrder) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ZStack {
                Color(hex: 0xF7F7F7)
                if let url = order.product?.image {
                    CachedImage(url: url)
                } else {
                    Image(systemName: "photo").foregroundStyle(appearance.muted)
                }
            }
            .frame(width: 76, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(order.product?.title?.trimmed.nilIfEmpty ?? "Jewellery request")
                        .font(appearance.body(14, weight: .bold))
                        .foregroundStyle(appearance.text)
                        .lineLimit(2)
                    Spacer(minLength: Spacing.sm)
                    if let status = order.status { OrderStatusBadge(status: status) }
                }

                Text("Order #\(order.id.prefix(8))" + (ChatTime.short(order.createdAt).map { " · \($0)" } ?? ""))
                    .font(appearance.body(11))
                    .foregroundStyle(appearance.muted)

                if let note = order.note?.trimmed.nilIfEmpty {
                    Text(note)
                        .font(appearance.body(11))
                        .foregroundStyle(appearance.muted)
                        .lineLimit(3)
                }

                if order.status == .rejected, let reason = order.rejectionReason?.trimmed.nilIfEmpty {
                    Text("Reason: \(reason)")
                        .font(appearance.body(11))
                        .foregroundStyle(Color.red)
                        .lineLimit(3)
                }

                if let next = RetailerOrdersView.storeStep(after: order.status) {
                    Button {
                        Task { await advance(order, to: next.status) }
                    } label: {
                        HStack(spacing: 6) {
                            if updatingID == order.id {
                                ProgressView().tint(.white).controlSize(.mini)
                            }
                            Text(next.label)
                                .font(appearance.body(12, weight: .bold))
                        }
                        .foregroundStyle(appearance.enabled ? appearance.onAccent : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(appearance.enabled ? appearance.accent : Palette.dark, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(updatingID != nil)
                    .padding(.top, 2)
                }
            }
        }
        .padding(appearance.enabled ? 24 : Spacing.md)
        .background(appearance.panel(), in: RoundedRectangle(cornerRadius: appearance.enabled ? appearance.cardRadius : 14))
        .overlay { RoundedRectangle(cornerRadius: appearance.enabled ? appearance.cardRadius : 14).stroke(appearance.enabled ? appearance.border : .clear, lineWidth: 1) }
    }

    private func advance(_ order: StaffOrder, to status: OrderStatus) async {
        guard updatingID == nil else { return }
        updatingID = order.id
        defer { updatingID = nil }
        do {
            try await OrdersAPI.setStatus(orderID: order.id, status: status)
        } catch {
            actionError = error.localizedDescription
        }
        await store.refreshOrders()
    }
}
