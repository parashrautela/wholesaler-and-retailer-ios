import SwiftUI

/// The Wholesaler Orders screen (`/dashboard/wholesaler/orders`): New,
/// Active, Completed and Rejected. Each card shows the design, the store
/// that asked and its note; tapping one opens the whole order, with its
/// timeline and whatever the wholesaler can do next.
struct WholesalerOrdersView: View {
    enum OrderTab: String, CaseIterable, Identifiable {
        case new, active, completed, rejected

        var id: String { rawValue }

        var title: String {
            switch self {
            case .new: "New Orders"
            case .active: "Active Orders"
            case .completed: "Completed"
            case .rejected: "Rejected"
            }
        }

        func contains(_ status: OrderStatus?) -> Bool {
            switch (self, status) {
            case (.new, .pending): true
            case (.active, .accepted), (.active, .inProduction), (.active, .packed), (.active, .dispatched): true
            case (.completed, .received), (.completed, .completed): true
            case (.rejected, .rejected): true
            default: false
            }
        }
    }

    @State private var selectedTab: OrderTab = .new
    @State private var orders: [WholesalerOrder] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var opened: WholesalerOrder?
    @State private var showInviteRetailer = false

    #if DEBUG
    /// Peeks only: orders to show instead of fetching.
    var peekOrders: [WholesalerOrder]?
    #endif

    private var filteredOrders: [WholesalerOrder] {
        orders.filter { selectedTab.contains($0.status) }
    }

    var body: some View {
        VStack(spacing: 0) {
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
        .task { await loadOrders() }
        .sheet(item: $opened) { order in
            WholesalerOrderDetail(order: order) {
                Task { await loadOrders() }
            }
        }
        .sheet(isPresented: $showInviteRetailer) {
            InviteRetailerSheet()
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoading && orders.isEmpty {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(Palette.dark)
            Spacer()
        } else if let errorMessage, orders.isEmpty {
            Spacer()
            VStack(spacing: Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.red)
                Text(errorMessage)
                    .font(.manrope(14))
                    .foregroundStyle(Palette.muted)
                Button("Retry") { Task { await loadOrders() } }
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
            ScrollView {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(filteredOrders) { order in
                        Button { opened = order } label: { WholesalerOrderCard(order: order) }
                            .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(.horizontal, Spacing.screenGutter)
                .padding(.bottom, Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .refreshTask { await loadOrders() }
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
            // No orders anywhere usually means no retailers yet — point at the
            // fix. An empty filter on an account that does have orders doesn't.
            Text(orders.isEmpty
                 ? "Orders from your retailers will show up here. Invite retailers to start receiving them."
                 : "No orders match this status at the moment.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            if orders.isEmpty {
                InviteRetailerButton { showInviteRetailer = true }
                    .padding(.top, Spacing.xs)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
    }

    private func loadOrders() async {
        #if DEBUG
        if let peekOrders {
            orders = peekOrders
            isLoading = false
            return
        }
        #endif
        isLoading = orders.isEmpty
        defer { isLoading = false }
        do {
            orders = try await OrdersAPI.fetchWholesalerOrders()
            errorMessage = nil
        } catch {
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Card

private struct WholesalerOrderCard: View {
    let order: WholesalerOrder

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            OrderDesignThumb(url: order.imageURL, size: 72)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Text(order.designTitle)
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(Palette.foreground)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.sm)
                    if let status = order.status { OrderStatusBadge(status: status) }
                }

                Label(order.storeLine, systemImage: "storefront")
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(Palette.foreground)
                    .lineLimit(1)

                if let note = order.note {
                    Text("“\(note)”")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                }

                Text("Order #\(order.shortID)" + (OrderTime.short(order.createdAt).map { " · \($0)" } ?? ""))
                    .font(.manrope(11))
                    .foregroundStyle(Palette.muted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .padding(.top, 4)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1) }
        .contentShape(.rect)
    }
}

struct OrderDesignThumb: View {
    let url: URL?
    var size: CGFloat

    var body: some View {
        ZStack {
            Color(hex: 0xF7F7F7)
            if let url {
                CachedImage(url: url)
            } else {
                Image(systemName: "photo").foregroundStyle(Palette.muted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Detail

/// One order in full: the design, the store, the note, where it has got to,
/// and the wholesaler's next step at the bottom.
struct WholesalerOrderDetail: View {
    @Environment(\.dismiss) private var dismiss
    let order: WholesalerOrder
    /// The list behind refreshes after any change.
    var onChanged: () -> Void

    @State private var working: OrderStatus?
    @State private var confirming: OrderStatus?
    @State private var showReject = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    storeSection
                    if let note = order.note {
                        section("Note from the store") {
                            Text(note)
                                .font(.manrope(14))
                                .foregroundStyle(Palette.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if order.status == .rejected {
                        section("Why it was rejected") {
                            Text(order.rejectionReason ?? "No reason was recorded.")
                                .font(.manrope(14))
                                .foregroundStyle(Color.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    section("Progress") { OrderTimeline(order: order) }
                }
                .padding(Spacing.screenGutter)
            }
            .scrollIndicators(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle("Order #\(order.shortID)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                confirming.map(Self.confirmTitle) ?? "",
                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                titleVisibility: .visible
            ) {
                if let next = confirming {
                    Button(Self.buttonTitle(next)) { Task { await move(to: next) } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showReject) {
                RejectOrderSheet { reason in
                    try await OrdersAPI.setStatus(orderID: order.id, status: .rejected, reason: reason)
                    onChanged()
                    dismiss()
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            OrderDesignThumb(url: order.imageURL, size: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(order.designTitle)
                    .font(.cirka(24))
                    .foregroundStyle(Palette.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let type = order.productType?.trimmed.nilIfEmpty {
                    Text(type.capitalized)
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                }
                if let status = order.status { OrderStatusBadge(status: status) }
            }
        }
    }

    private var storeSection: some View {
        section("Store") {
            VStack(alignment: .leading, spacing: 4) {
                Text(order.storeName?.trimmed.nilIfEmpty ?? "Retail store")
                    .font(.manrope(15, weight: .bold))
                    .foregroundStyle(Palette.foreground)
                if let city = order.storeCity {
                    Text(city)
                        .font(.manrope(13))
                        .foregroundStyle(Palette.muted)
                }
                if let who = order.placedBy?.trimmed.nilIfEmpty {
                    Text(order.placedByStaff ? "Placed by \(who), store staff" : "Placed by \(who), owner")
                        .font(.manrope(13))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title.uppercased())
                .font(.manrope(11, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Palette.muted)
            content()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Actions

    @ViewBuilder
    private var actionBar: some View {
        let next = Self.nextStep(after: order.status)
        if order.status == .pending || next != nil || errorMessage != nil || order.status == .dispatched {
            VStack(spacing: Spacing.sm) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.manrope(12))
                        .foregroundStyle(Color.red)
                        .multilineTextAlignment(.center)
                }
                if order.status == .pending {
                    HStack(spacing: Spacing.sm) {
                        actionButton("Reject", style: .destructive) { showReject = true }
                        actionButton("Accept Order", style: .primary, for: .accepted) { confirming = .accepted }
                    }
                } else if let next {
                    actionButton(Self.buttonTitle(next), style: .primary, for: next) { confirming = next }
                } else if order.status == .dispatched {
                    Text("Dispatched — waiting for the store to confirm they received it.")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Spacing.screenGutter)
            .padding(.vertical, Spacing.md)
            .background(.bar)
        }
    }

    private enum ActionStyle { case primary, destructive }

    private func actionButton(_ title: String, style: ActionStyle, for status: OrderStatus? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let status, working == status {
                    ProgressView().tint(style == .primary ? .white : .red).controlSize(.small)
                }
                Text(title).font(.manrope(15, weight: .bold))
            }
            .foregroundStyle(style == .primary ? Color.white : Color.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(style == .primary ? Palette.dark : Color.red.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(working != nil)
    }

    /// The wholesaler's next step once an order is accepted. Production is
    /// optional in the server's rules, so it isn't forced here.
    static func nextStep(after status: OrderStatus?) -> OrderStatus? {
        switch status {
        case .accepted, .inProduction: .packed
        case .packed: .dispatched
        default: nil
        }
    }

    static func buttonTitle(_ status: OrderStatus) -> String {
        switch status {
        case .accepted: "Accept & Start Production"
        case .packed: "Mark as Packed"
        case .dispatched: "Mark as Dispatched"
        default: "Update"
        }
    }

    static func confirmTitle(_ status: OrderStatus) -> String {
        switch status {
        case .accepted: "Accept this order?"
        case .packed: "Has this order been packed?"
        case .dispatched: "Has this order been dispatched?"
        default: "Update this order?"
        }
    }

    private func move(to status: OrderStatus) async {
        guard working == nil else { return }
        working = status
        errorMessage = nil
        defer { working = nil }
        do {
            try await OrdersAPI.setStatus(orderID: order.id, status: status)
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            onChanged()
        }
    }
}

// MARK: - Timeline

private struct OrderTimeline: View {
    let order: WholesalerOrder

    private struct Step: Identifiable {
        let id: String
        let title: String
        let at: String?
        var failed = false
    }

    /// Every step the order can pass through; the ones it has reached carry
    /// their time. In production only appears when it was actually used.
    private var steps: [Step] {
        var all = [Step(id: "submitted", title: "Order submitted", at: order.createdAt)]
        if order.status == .rejected {
            all.append(Step(id: "rejected", title: "Rejected", at: order.rejectedAt, failed: true))
            return all
        }
        all.append(Step(id: "accepted", title: "Accepted", at: order.acceptedAt))
        if order.productionAt != nil {
            all.append(Step(id: "production", title: "In production", at: order.productionAt))
        }
        all += [
            Step(id: "packed", title: "Packed", at: order.packedAt),
            Step(id: "dispatched", title: "Dispatched", at: order.dispatchedAt),
            Step(id: "received", title: "Received by store", at: order.receivedAt),
            Step(id: "completed", title: "Completed", at: order.completedAt),
        ]
        return all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                let done = step.at != nil
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(step.failed ? Color.red : (done ? Palette.dark : Color.clear))
                            .overlay { Circle().stroke(done ? Color.clear : Palette.border, lineWidth: 1.5) }
                            .frame(width: 12, height: 12)
                            .padding(.top, 3)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(steps[index + 1].at != nil ? Palette.dark : Palette.border)
                                .frame(width: 1.5)
                                .frame(minHeight: 26)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.manrope(14, weight: done ? .semibold : .regular))
                            .foregroundStyle(step.failed ? Color.red : (done ? Palette.foreground : Palette.muted))
                        Text(OrderTime.full(step.at) ?? "Not yet")
                            .font(.manrope(12))
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.bottom, Spacing.sm)
                }
            }
        }
    }
}

// MARK: - Reject

/// Rejecting needs a reason. The common ones are chips; one at a time — to
/// pick another, clear the first. Details can be added underneath.
struct RejectOrderSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Throws to keep the sheet open and show what went wrong.
    let onConfirm: (String) async throws -> Void

    static let reasons = [
        "Design out of stock",
        "Can't meet the delivery time",
        "Customisation not possible",
        "Metal rate has changed",
        "Below minimum order",
    ]

    @State private var chosen: String?
    @State private var details = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var reason: String? {
        guard let chosen else { return nil }
        let extra = details.trimmed
        return extra.isEmpty ? chosen : "\(chosen) — \(extra)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Why can't this order be fulfilled? The store will see this.")
                        .font(.manrope(14))
                        .foregroundStyle(Palette.muted)

                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(Self.reasons, id: \.self) { item in
                            chip(item)
                        }
                    }

                    if chosen != nil {
                        Text("Tap the selected reason again to choose a different one.")
                            .font(.manrope(11))
                            .foregroundStyle(Palette.muted)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add details (optional)")
                            .font(.manrope(12, weight: .semibold))
                            .foregroundStyle(Palette.foreground)
                        TextField("e.g. back in stock on 5 Oct", text: $details, axis: .vertical)
                            .font(.manrope(14))
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1) }
                    }
                }
                .padding(Spacing.screenGutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background.ignoresSafeArea())
            // Pinned above the keyboard, so it can always be reached.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Spacing.sm) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.manrope(12))
                            .foregroundStyle(Color.red)
                            .multilineTextAlignment(.center)
                    }
                    Button { Task { await confirm() } } label: {
                        HStack(spacing: 8) {
                            if isSaving { ProgressView().tint(.white).controlSize(.small) }
                            Text(isSaving ? "Rejecting…" : "Confirm Rejection")
                                .font(.manrope(15, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(reason == nil ? Color.red.opacity(0.35) : Color.red,
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(reason == nil || isSaving)
                }
                .padding(.horizontal, Spacing.screenGutter)
                .padding(.vertical, Spacing.md)
                .background(.bar)
            }
            .navigationTitle("Reject Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        .presentationDetents([.large])
    }

    private func chip(_ item: String) -> some View {
        let isChosen = chosen == item
        let isLocked = chosen != nil && !isChosen
        return Button {
            chosen = isChosen ? nil : item
        } label: {
            HStack(spacing: 6) {
                Text(item)
                if isChosen {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
            }
            .font(.manrope(13, weight: .semibold))
            .foregroundStyle(isChosen ? Color.white : Palette.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isChosen ? Palette.dark : Color.white, in: Capsule())
            .overlay { Capsule().stroke(isChosen ? Color.clear : Palette.border, lineWidth: 1) }
            .opacity(isLocked ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLocked || isSaving)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityHint(isLocked ? "Clear the selected reason first" : "")
    }

    private func confirm() async {
        guard let reason, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await onConfirm(reason)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Lays chips out in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let current = rows[rows.count - 1]
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows.removeLast()
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows.append(row)
        }
        return rows
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

/// Server timestamps are UTC with microseconds; show them in local time.
enum OrderTime {
    static func short(_ raw: String?) -> String? { ChatTime.short(raw) }

    static func full(_ raw: String?) -> String? {
        guard let date = ChatTime.date(raw) else { return nil }
        return date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }
}
