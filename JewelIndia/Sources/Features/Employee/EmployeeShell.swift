import SwiftUI

enum EmployeeTab: String, CaseIterable, Identifiable {
    case home, catalogue, queries, orders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .catalogue: "Catalogue"
        case .queries: "Queries"
        case .orders: "Orders"
        }
    }

    /// The web's own glyphs (`EmployeeTopNav.jsx`), as vector assets.
    var icon: String {
        switch self {
        case .home: "EmpNavHome"
        case .catalogue: "EmpNavCatalogue"
        case .queries: "EmpNavQueries"
        case .orders: "EmpNavOrders"
        }
    }
}

/// The employee view (`/dashboard/employee`): four pages under the web's
/// floating glass pill instead of a system tab bar, the amber "EMPLOYEE VIEW
/// ACTIVE" marker and blue Dashboard button for a retailer, and red dots
/// when Queries or Orders has something new.
struct EmployeeShell: View {
    @Environment(SessionStore.self) private var session
    @State private var store: EmployeeStore
    @State private var selection: EmployeeTab
    /// Pages are built on first visit and then kept, like tabs.
    @State private var visited: Set<EmployeeTab>
    @State private var width: CGFloat = 0

    init() {
        _store = State(initialValue: EmployeeStore())
        _selection = State(initialValue: .home)
        _visited = State(initialValue: [.home])
    }

    #if DEBUG
    /// Peeks only: start from a seeded store.
    init(store: EmployeeStore, tab: EmployeeTab = .home) {
        _store = State(initialValue: store)
        _selection = State(initialValue: tab)
        _visited = State(initialValue: [tab])
    }
    #endif

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
            case .failed(let message):
                failed(message)
            case .ready(let current):
                pages(current)
            }
        }
        .environment(store)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .task {
            // Staff devices count towards the store's, the same as the owner's.
            StoreActivity.registerDevice()
            if store.session == nil { await store.load(sessionStore: session) }
        }
    }

    private func pages(_ current: EmployeeSession) -> some View {
        ZStack {
            ForEach(EmployeeTab.allCases) { tab in
                if visited.contains(tab) {
                    page(tab)
                        .opacity(selection == tab ? 1 : 0)
                        .allowsHitTesting(selection == tab && store.routes.isEmpty)
                        .accessibilityHidden(selection != tab || !store.routes.isEmpty)
                }
            }
            ForEach(store.routes) { route in
                routePage(route)
                    .allowsHitTesting(route == store.routes.last)
                    .accessibilityHidden(route != store.routes.last)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.routes)
        .overlay(alignment: .bottom) {
            if store.routes.isEmpty {
                EmployeePillNav(
                    selection: selection,
                    width: width,
                    queriesDot: store.hasUnreadQueries,
                    ordersDot: store.hasUnreadOrders && selection != .orders,
                    showsDashboardButton: current.isRetailer,
                    onSelect: select,
                    onDashboard: { Task { await switchToRetailerView() } }
                )
                .padding(.bottom, 20)
            }
        }
        .onChange(of: store.tabRequest) { _, tab in
            guard let tab else { return }
            store.tabRequest = nil
            select(tab)
        }
        .overlay(alignment: .topTrailing) {
            if current.isRetailer {
                EmployeeViewBanner()
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }
        }
    }

    @ViewBuilder
    private func page(_ tab: EmployeeTab) -> some View {
        switch tab {
        case .home:
            EmployeeHomeView(onOpenCatalogue: { select(.catalogue) })
        case .catalogue:
            EmployeeCatalogueView()
        case .queries:
            ComingSoonView(title: tab.title, symbol: "bubble.left",
                           message: "Conversations with your wholesalers will show up here soon.")
        case .orders:
            ComingSoonView(title: tab.title, symbol: "shippingbox",
                           message: "Orders placed for your store will show up here soon.")
        }
    }

    @ViewBuilder
    private func routePage(_ route: EmployeeRoute) -> some View {
        switch route {
        case .review(let productID):
            EmployeeReviewView(productID: productID)
        }
    }

    private func select(_ tab: EmployeeTab) {
        visited.insert(tab)
        selection = tab
        if tab == .orders { store.markOrdersChecked() }
        Task { await store.refreshDots() }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: Spacing.base) {
            Text(message)
                .font(.manrope(14))
                .foregroundStyle(Color(hex: 0x6B7280))
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await store.load(sessionStore: session) } }
                .font(.manrope(14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x111827))
            Button("Sign Out") { Task { await session.signOut() } }
                .font(.manrope(13))
                .foregroundStyle(Color(hex: 0x6B7280))
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    /// The web posts `/api/auth/toggle-view {mode:"retailer"}` so its server
    /// can read a cookie; on device the preference is local.
    private func switchToRetailerView() async {
        guard let id = session.user?.id else { return }
        ViewModeStore.set(.retailer, for: id)
        await session.refreshDestination()
    }
}

// MARK: - Floating pill

/// `EmployeeBottomNav`: a glass capsule floating 20pt above the bottom,
/// sized to its contents. Icons only on phones; labels from 640pt wide.
struct EmployeePillNav: View {
    let selection: EmployeeTab
    let width: CGFloat
    let queriesDot: Bool
    let ordersDot: Bool
    let showsDashboardButton: Bool
    let onSelect: (EmployeeTab) -> Void
    let onDashboard: () -> Void

    private var showsLabels: Bool { width >= 640 }
    private var isMedium: Bool { width >= 768 }
    private var isLarge: Bool { width >= 1024 }

    var body: some View {
        HStack(spacing: isLarge ? 4 : 2) {
            ForEach(EmployeeTab.allCases) { tab in
                item(tab)
            }
            if showsDashboardButton {
                dashboardButton
                    .padding(.leading, 4)
            }
        }
        .padding(6)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(.white.opacity(0.55))
            }
        }
        .overlay { Capsule().stroke(.white.opacity(0.45), lineWidth: 1) }
        .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1.5)
    }

    private func item(_ tab: EmployeeTab) -> some View {
        let active = tab == selection
        let dot = (tab == .queries && queriesDot) || (tab == .orders && ordersDot)
        let fontSize: CGFloat = isLarge ? 13 : (isMedium ? 12 : 11)

        return Button { onSelect(tab) } label: {
            HStack(spacing: isLarge ? 8 : 6) {
                Image(tab.icon)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 17, height: 17)
                    .opacity(active ? 1 : 0.7)
                    .overlay(alignment: .topTrailing) {
                        if dot {
                            EmployeePingDot().offset(x: 4, y: -4)
                        }
                    }
                if showsLabels {
                    Text(tab.title)
                        .font(.manrope(fontSize, weight: active ? .semibold : .medium))
                        .kerning(fontSize * 0.01)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(active ? Color(hex: 0x111827) : Color(hex: 0x6B7280))
            .padding(.horizontal, isLarge ? 20 : (isMedium ? 16 : 10))
            .padding(.vertical, isLarge ? 10 : (isMedium ? 8 : 6))
            .background {
                if active {
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                }
            }
            .contentShape(Capsule())
            .animation(.easeInOut(duration: 0.2), value: active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title + (dot ? ", new activity" : ""))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var dashboardButton: some View {
        let fontSize: CGFloat = isLarge ? 13 : (isMedium ? 12 : 11)
        return Button(action: onDashboard) {
            HStack(spacing: isLarge ? 8 : 6) {
                Image("EmpNavPerson")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 15, height: 15)
                Text(isLarge ? "Take me to dashboard" : "Dashboard")
                    .font(.manrope(fontSize, weight: .semibold))
                    .kerning(fontSize * 0.01)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isLarge ? 20 : (isMedium ? 16 : 12))
            .padding(.vertical, isLarge ? 10 : (isMedium ? 8 : 6))
            .background(
                LinearGradient(colors: [Color(hex: 0x3B82F6), Color(hex: 0x1D4ED8)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
            .shadow(color: Color(hex: 0x1D4ED8).opacity(0.2), radius: 6, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Tailwind's `animate-ping` behind a solid red dot.
private struct EmployeePingDot: View {
    private struct Ping {
        var scale: CGFloat = 1
        var opacity: Double = 0.75
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xFF6467))
                .keyframeAnimator(initialValue: Ping(), repeating: true) { content, value in
                    content.scaleEffect(value.scale).opacity(value.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(2, duration: 0.75)
                        CubicKeyframe(2, duration: 0.25)
                    }
                    KeyframeTrack(\.opacity) {
                        CubicKeyframe(0, duration: 0.75)
                        CubicKeyframe(0, duration: 0.25)
                    }
                }
            Circle()
                .fill(Color(hex: 0xFB2C36))
                .overlay { Circle().stroke(.white, lineWidth: 1) }
        }
        .frame(width: 8, height: 8)
        .allowsHitTesting(false)
    }
}

// MARK: - Retailer marker

/// `EmployeeLayout.jsx`'s fixed capsule. Shown only to a retailer, floats
/// over everything, and takes no taps.
struct EmployeeViewBanner: View {
    @State private var pulse = false
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: 0xD97706))
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1.1 : 0.95)
                .opacity(pulse ? 1 : 0.5)
            Text("EMPLOYEE VIEW ACTIVE")
                .font(.manrope(12, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Color(hex: 0xB45309))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hex: 0xFEF3C7), in: Capsule())
        .overlay { Capsule().stroke(Color(hex: 0xF59E0B), lineWidth: 1) }
        .shadow(color: Color(hex: 0xF59E0B).opacity(0.1), radius: 7, y: 10)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -8)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Employee view active")
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
