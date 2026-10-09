import Foundation

@main struct MarketplaceContractTests {
    static func decode(_ json: String) throws -> JewelAPI.PaginatedMarketplaceResponse {
        try JSONDecoder().decode(JewelAPI.PaginatedMarketplaceResponse.self, from: Data(json.utf8))
    }

    static func main() throws {
        let legacy = try decode(#"{"products":[{"id":"necklace","title":"Temple necklace","jewellery_type":"Necklace","metal_purity":"22kt"},{"id":"ring","title":"Ruby ring","jewellery_type":"Ring"}],"selected_product_ids":["necklace"]}"#)
        precondition(legacy.isLegacyContract && !legacy.hasMore && legacy.pageSize == 2)
        precondition(legacy.selectedProductIDs == ["necklace"])
        print("PASS: deployed legacy response decodes without pagination fields")
        let filtered = legacy.filteringLegacy(category: "necklace", search: "temple")
        precondition(filtered.products.map(\.id) == ["necklace"])
        precondition(filtered.fallbackCategories?.count == 2)
        precondition(legacy.filteringLegacy(category: "Ring", search: "temple").products.isEmpty)
        print("PASS: legacy category/search filtering retains the full category list")
        let page = try decode(#"{"products":[{"id":"p1"}],"selected_product_ids":[],"has_more":true,"next_cursor":"cursor","page_size":1}"#)
        precondition(!page.isLegacyContract && page.hasMore && page.nextCursor == "cursor")
        precondition(page.filteringLegacy(category: "Ring", search: "missing").products.count == 1)
        print("PASS: v2 pagination and server filters remain authoritative")
        let empty = try decode(#"{"products":[],"selected_product_ids":[]}"#)
        precondition(empty.products.isEmpty && empty.pageSize == 0)
        print("PASS: an empty legacy catalogue is valid")
        for bad in [#"{"selected_product_ids":[]}"#, #"{"products":[{}],"selected_product_ids":[]}"#, #"{"products":[],"selected_product_ids":[],"has_more":true}"#] {
            do { _ = try decode(bad); fatalError("Malformed catalogue was accepted") }
            catch is DecodingError { }
        }
        print("PASS: missing product IDs/content and malformed v2 contracts still fail")
    }
}
