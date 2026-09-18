import Foundation
import Observation

/// Everything the employee view shares across its tabs: who is looking, at
/// which store, in which theme, and whether Queries or Orders has something
/// new. The web works this out in its server layout on every load
/// (`app/dashboard/employee/layout.jsx`).
///
/// It also holds what the web keeps in the browser tab: the pieces picked
/// by long-press (`sessionStorage.employee_selected_products`, gone when the
/// app closes, as the tab's storage is) and the full-screen pages open over
/// the tabs.
@MainActor
@Observable
final class EmployeeStore {
    enum Phase: Equatable {
        case loading
        case ready(EmployeeSession)
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var hasUnreadQueries = false
    private(set) var latestOrderUpdate: Date?
    private(set) var ordersLastChecked: Date?

    /// Product ids picked by long-press, oldest first.
    private(set) var selectedProductIDs: [String] = []
    /// Products already loaded somewhere, so a detail page can open at once.
    private(set) var productCache: [String: Product] = [:]
    /// Full-screen pages over the tabs, the top one showing. The web hides
    /// its bottom bar on these (`hideNavbar`).
    private(set) var routes: [EmployeeRoute] = []
    /// A page asking the shell to change tab.
    var tabRequest: EmployeeTab?
    /// "Chat with us" was tapped on this product; Queries opens its
    /// conversation (`/dashboard/employee/messages?productId=`).
    var pendingChatProductID: String?

    init() {}

    var session: EmployeeSession? {
        if case .ready(let session) = phase { return session }
        return nil
    }

    /// The web's rule: a dot when an order changed after the tab was last
    /// opened, or when it has never been opened.
    var hasUnreadOrders: Bool {
        guard let latestOrderUpdate else { return false }
        guard let ordersLastChecked else { return true }
        return latestOrderUpdate > ordersLastChecked
    }

    func load(sessionStore: SessionStore) async {
        guard let user = sessionStore.user else {
            phase = .failed("Please sign in again.")
            return
        }
        do {
            let isRetailer = await AuthRouter.resolveRole(for: user) == .retailer
            let session = try await EmployeeAPI.resolveSession(userID: user.id, isRetailer: isRetailer)
            phase = .ready(session)
            ordersLastChecked = UserDefaults.standard.object(forKey: session.storageKey) as? Date
            await refreshDots()
        } catch {
            if case .ready = phase { return }
            phase = .failed(error.localizedDescription)
        }
    }

    func refreshDots() async {
        guard let session else { return }
        async let queries = EmployeeAPI.hasUnreadQueries(session)
        async let orders = EmployeeAPI.latestOrderUpdate(session)
        hasUnreadQueries = await queries
        latestOrderUpdate = await orders
    }

    /// Opening Orders clears its dot, as visiting `/dashboard/employee/orders` does.
    func markOrdersChecked() {
        guard let session else { return }
        let now = Date()
        ordersLastChecked = now
        UserDefaults.standard.set(now, forKey: session.storageKey)
    }

    // MARK: - Selection

    /// Adds or removes a product; true when it is now selected.
    @discardableResult
    func toggleSelection(_ id: String) -> Bool {
        if let index = selectedProductIDs.firstIndex(of: id) {
            selectedProductIDs.remove(at: index)
            return false
        }
        selectedProductIDs.append(id)
        return true
    }

    func removeSelection(_ id: String) {
        selectedProductIDs.removeAll { $0 == id }
    }

    func clearSelection() {
        selectedProductIDs = []
    }

    func cache(_ products: [Product]) {
        for product in products { productCache[product.id] = product }
    }

    // MARK: - Pages

    func push(_ route: EmployeeRoute) {
        routes.append(route)
    }

    func pop() {
        _ = routes.popLast()
    }

    func openChat(productID: String) {
        pendingChatProductID = productID
        routes = []
        tabRequest = .queries
    }

    /// `/dashboard/employee`: every page closed, Home showing.
    func goHome() {
        routes = []
        tabRequest = .home
    }

    #if DEBUG
    /// Peeks only: designs to show instead of fetching.
    private(set) var peekDesigns: [RetailerDesign]?

    /// Peeks only.
    func seedForPeek(products: [Product], selected: [String] = [], routes: [EmployeeRoute] = []) {
        peekProducts = products
        cache(products)
        selectedProductIDs = selected
        self.routes = routes
    }

    /// Peeks only: the store's shortlist, instead of fetching.
    private(set) var peekProducts: [Product]?

    /// Peeks only.
    func seedForPeek(designs: [RetailerDesign]? = nil, _ session: EmployeeSession, unreadQueries: Bool = false, unreadOrders: Bool = false) {
        phase = .ready(session)
        peekDesigns = designs
        hasUnreadQueries = unreadQueries
        latestOrderUpdate = unreadOrders ? Date() : nil
        ordersLastChecked = nil
    }
    #endif
}

/// A full-screen page over the employee tabs.
enum EmployeeRoute: Hashable, Identifiable {
    /// `/dashboard/employee/playground/review[?productId=]`: one product in
    /// detail, or the long-pressed pieces when there is no product.
    case review(productID: String?)

    var id: String {
        switch self {
        case .review(let productID): "review-\(productID ?? "")"
        }
    }
}
