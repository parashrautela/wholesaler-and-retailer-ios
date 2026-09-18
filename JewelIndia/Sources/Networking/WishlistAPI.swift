import Foundation
import Supabase

/// A store's customers and their boards (`retailer_customers`,
/// `customer_boards`, `customer_board_items`).
///
/// The app never sends a store id: each table defaults `retailer_id` to
/// `my_retailer_id()` and RLS compares against the same function, so a row
/// can only ever land in — or be read from — the caller's own store. That
/// holds for the owner and for their active staff alike.
enum WishlistAPI {
    private static var db: SupabaseClient { SupabaseManager.client }

    // MARK: - Customers

    /// The store's customers, newest first, each with how many designs are
    /// saved across their boards.
    static func fetchCustomers() async throws -> [StoreCustomer] {
        try await db.from("retailer_customers")
            .select("id, name, phone, note, created_at, customer_boards(customer_board_items(product_id))")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// The server gives every new customer a first board, "Wishlist".
    static func addCustomer(name: String, phone: String?, note: String?) async throws {
        struct NewCustomer: Encodable {
            let name: String
            let phone: String?
            let note: String?
        }
        try await db.from("retailer_customers")
            .insert(NewCustomer(name: name, phone: phone, note: note))
            .execute()
    }

    /// Takes the customer's boards and saved designs with them.
    static func deleteCustomer(id: String) async throws {
        try await db.from("retailer_customers")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Boards

    /// A customer's boards, oldest first, with the designs on each.
    static func fetchBoards(customerID: String) async throws -> [CustomerBoard] {
        let rows: [BoardRow] = try await db.from("customer_boards")
            .select("id, title, customer_board_items(product_id, created_at)")
            .eq("customer_id", value: customerID)
            .order("created_at", ascending: true)
            .execute()
            .value

        let ids = Set(rows.flatMap { $0.items.map(\.productID) })
        let products = try await fetchProducts(ids: Array(ids))
        let byID = Dictionary(uniqueKeysWithValues: products.map { ($0.id.lowercased(), $0) })

        return rows.map { row in
            CustomerBoard(
                id: row.id,
                title: row.title,
                // Newest saved first. A design the wholesaler has since
                // unpublished drops out rather than showing as a blank tile.
                products: row.items
                    .sorted { $0.createdAt > $1.createdAt }
                    .compactMap { byID[$0.productID.lowercased()] }
            )
        }
    }

    static func addBoard(customerID: String, title: String) async throws {
        struct NewBoard: Encodable {
            let customer_id: String
            let title: String
        }
        try await db.from("customer_boards")
            .insert(NewBoard(customer_id: customerID, title: title))
            .execute()
    }

    static func deleteBoard(id: String) async throws {
        try await db.from("customer_boards")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Designs on a board

    static func setDesign(_ productID: String, onBoard boardID: String, saved: Bool) async throws {
        if saved {
            struct NewItem: Encodable {
                let board_id: String
                let product_id: String
            }
            // Saving twice is not an error — the design is simply still there.
            try await db.from("customer_board_items")
                .upsert(NewItem(board_id: boardID, product_id: productID),
                        onConflict: "board_id,product_id", ignoreDuplicates: true)
                .execute()
        } else {
            try await db.from("customer_board_items")
                .delete()
                .eq("board_id", value: boardID)
                .eq("product_id", value: productID)
                .execute()
        }
    }

    private static func fetchProducts(ids: [String]) async throws -> [Product] {
        guard !ids.isEmpty else { return [] }
        return try await db.from("products")
            .select()
            .eq("is_published", value: true)
            .in("id", values: ids)
            .execute()
            .value
    }

    private struct BoardRow: Decodable {
        let id: String
        let title: String
        let items: [Item]

        struct Item: Decodable {
            let productID: String
            let createdAt: String

            enum CodingKeys: String, CodingKey {
                case productID = "product_id"
                case createdAt = "created_at"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, title
            case items = "customer_board_items"
        }
    }
}

// MARK: - Models

struct StoreCustomer: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let phone: String?
    let note: String?
    let designCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, phone, note
        case boards = "customer_boards"
    }

    init(id: String, name: String, phone: String?, note: String?, designCount: Int) {
        self.id = id
        self.name = name
        self.phone = phone
        self.note = note
        self.designCount = designCount
    }

    init(from decoder: Decoder) throws {
        struct Board: Decodable {
            let customer_board_items: [Item]
            struct Item: Decodable { let product_id: String }
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        let boards = try c.decodeIfPresent([Board].self, forKey: .boards) ?? []
        // The same design on two boards is still one design the customer likes.
        designCount = Set(boards.flatMap { $0.customer_board_items.map(\.product_id) }).count
    }
}

struct CustomerBoard: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var products: [Product]
}
