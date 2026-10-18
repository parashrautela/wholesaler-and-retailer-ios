import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

@main struct Checks {
    static func product(_ id: String, published: Bool?) throws -> Product {
        var row: [String: Any] = ["id": id, "title": "Design \(id)"]
        if let published { row["is_published"] = published }
        return try JSONDecoder().decode(Product.self, from: JSONSerialization.data(withJSONObject: row))
    }

    static func main() throws {
        var selection = CatalogueSelection()
        precondition(selection.ids.isEmpty && selection.products.isEmpty)
        for published in [false, nil] as [Bool?] {
            let draft = try product("draft", published: published)
            precondition(selection.toggle(draft) == Copy.CatalogueShare.selectUnpublished)
            precondition(selection.ids.isEmpty)
        }
        for id in 0..<50 {
            let design = try product(String(id), published: true)
            precondition(selection.toggle(design) == nil)
        }
        precondition(selection.ids == (0..<50).map(String.init))
        precondition(selection.products.map(\.id) == selection.ids, "Selections must survive replacement of the loaded category")
        let extra = try product("51", published: true)
        let first = try product("0", published: true)
        precondition(selection.toggle(extra) == Copy.CatalogueShare.selectLimit)
        precondition(selection.ids.count == 50)
        precondition(selection.toggle(first) == nil, "Can deselect at the limit")
        precondition(selection.toggle(first) == nil)
        precondition(selection.ids.last == "0", "Reselecting appends to display order")
        precondition(selection.products.map(\.id) == selection.ids)
        precondition(Copy.CatalogueShare.shareBarButton(1) == "Share 1 design")
        precondition(Copy.CatalogueShare.shareBarButton(2) == "Share 2 designs")
        selection = CatalogueSelection()
        precondition(selection.ids.isEmpty && selection.products.isEmpty, "Cancel clears the snapshots too")
        print("PASS: published-only selection, 50-design limit, deselection, selection order, retained snapshots, reset, copy")
    }
}
