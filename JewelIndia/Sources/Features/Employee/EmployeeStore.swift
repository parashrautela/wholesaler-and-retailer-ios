import Foundation
import Observation

/// Everything the employee view shares across its tabs: who is looking, at
/// which store, in which theme, and whether Queries or Orders has something
/// new. The web works this out in its server layout on every load
/// (`app/dashboard/employee/layout.jsx`).
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

    #if DEBUG
    /// Peeks only: designs to show instead of fetching.
    private(set) var peekDesigns: [RetailerDesign]?

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
