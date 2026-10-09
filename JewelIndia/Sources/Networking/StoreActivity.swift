import Foundation
import Supabase
import UIKit

/// What a store does, recorded for Business Insights (`store_events`), and
/// the devices it does it on (`store_devices`).
///
/// Both are records only — nothing is limited or charged from them yet — and
/// neither may ever get in the way: every call is fire-and-forget, and a
/// failure is dropped silently. The server fills in the store and the actor.
enum StoreActivity {
    private static var db: SupabaseClient { SupabaseManager.client }

    /// `<noun>.<verb>`, lowercase — the table rejects anything else.
    enum Event: String {
        case designViewed = "design.viewed"
        case designShortlisted = "design.shortlisted"
        case designSavedToBoard = "wishlist.design_saved"
        case customerAdded = "customer.added"
        case orderRequested = "order.requested"
        case imageExported = "chamak.exported"
    }

    static func log(_ event: Event, productID: String? = nil, customerID: String? = nil) {
        struct Row: Encodable {
            let event: String
            let product_id: String?
            let customer_id: String?
        }
        let row = Row(event: event.rawValue, product_id: productID, customer_id: customerID)
        Task.detached(priority: .background) {
            _ = try? await db.from("store_events").insert(row).execute()
        }
    }

    /// Notes this device against the store. `identifierForVendor` is scoped to
    /// this developer's apps and resets on reinstall, which is as much as a
    /// device count needs.
    @MainActor
    static func registerDevice() {
        guard let deviceID = UIDevice.current.identifierForVendor?.uuidString else { return }
        let info = Bundle.main.infoDictionary
        let version = [info?["CFBundleShortVersionString"], info?["CFBundleVersion"]]
            .compactMap { $0 as? String }
            .joined(separator: " ")
        let params = [
            "p_device_id": deviceID,
            "p_model": UIDevice.current.model,
            "p_app_version": version,
        ]
        Task.detached(priority: .background) {
            _ = try? await db.rpc("register_device", params: params).execute()
        }
    }
}
