import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum AppConfig { static let siteURL = URL(string: "https://catalogue.test")! }
enum SupabaseManager { static let client = Client() }
struct Client { let auth = Auth() }
struct Auth { var session: AuthSession { get async throws { AuthSession(accessToken: "test-session") } } }
struct AuthSession { let accessToken: String }

final class Reply: URLProtocol, @unchecked Sendable {
    static var status = 200
    static var body = Data()
    static var request: URLRequest?
    static var requestBody = Data()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "catalogue.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.request = request
        Self.requestBody = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&bytes, maxLength: bytes.count)
                if n <= 0 { break }
                Self.requestBody.append(contentsOf: bytes.prefix(n))
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Checks {
    static func product(_ id: String, published: Bool?) throws -> Product {
        var row: [String: Any] = ["id": id, "title": "Design \(id)"]
        if let published { row["is_published"] = published }
        return try JSONDecoder().decode(Product.self, from: JSONSerialization.data(withJSONObject: row))
    }

    static func main() async throws {
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
        URLProtocol.registerClass(Reply.self)
        defer { URLProtocol.unregisterClass(Reply.self) }
        let token = String(repeating: "a", count: 64)
        func share(path: String? = nil, expiry: String = "2099-01-01T00:00:00.000Z", revoked: String? = nil, views: Int = 0) throws -> CatalogueShare {
            var row: [String: Any] = ["id": "share-id", "item_count": 2, "max_viewers": 2, "views_used": views, "expires_at": expiry]
            row["link_path"] = path
            row["revoked_at"] = revoked
            return try JSONDecoder().decode(CatalogueShare.self, from: JSONSerialization.data(withJSONObject: row))
        }
        let active = try share(path: "/share/catalogue#" + token)
        precondition(active.url?.absoluteString == "https://catalogue.test/share/catalogue#" + token)
        for path in ["https://evil.test/#" + token, "/share/catalogue#" + token + "\n", "/share/catalogue#" + token.uppercased(), "/share/catalogue#abc", "/share/wishlist#" + token] {
            let invalid = try share(path: path)
            precondition(invalid.url == nil, "Invalid link path accepted")
        }
        let revoked = try share(revoked: "2026-01-01", views: 2)
        let expired = try share(expiry: "2000-01-01T00:00:00Z", views: 2)
        let full = try share(views: 2)
        precondition(active.status == "Active" && active.canRevoke)
        precondition(revoked.status == "Revoked" && !revoked.canRevoke)
        precondition(expired.status == "Expired" && !expired.canRevoke)
        precondition(full.status == "All slots used" && !full.canRevoke)
        precondition(active.expiry != nil && expired.expiry != nil)
        precondition(Copy.CatalogueShare.shareText(title: nil, url: active.url!) == active.url!.absoluteString)
        precondition(Copy.CatalogueShare.shareText(title: "For you", url: active.url!) == "For you — " + active.url!.absoluteString)
        Reply.status = 201
        Reply.body = try JSONSerialization.data(withJSONObject: ["ok": true, "id": "share-id", "title": "Designs for you", "item_count": 2, "max_viewers": 2, "views_used": 0, "expires_at": "2099-01-01T00:00:00Z", "link_path": "/share/catalogue#" + token])
        _ = try await CatalogueShareAPI.createShare(productIDs: ["second", "first"], viewers: 2, minutes: 60, title: "  For you  ")
        let body = try JSONSerialization.jsonObject(with: Reply.requestBody) as! [String: Any]
        precondition(body["product_ids"] as? [String] == ["second", "first"])
        precondition(body["max_viewers"] as? Int == 2 && body["duration_minutes"] as? Int == 60 && body["title"] as? String == "For you")
        precondition(Reply.request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-session")
        precondition(Reply.request?.httpMethod == "POST" && Reply.request?.url?.path == "/api/catalogue-shares")
        _ = try await CatalogueShareAPI.createShare(productIDs: ["first"], viewers: 1, minutes: 1440, title: "  ")
        let untitled = try JSONSerialization.jsonObject(with: Reply.requestBody) as! [String: Any]
        precondition(untitled["title"] == nil)
        Reply.status = 200; Reply.body = Data(#"{"ok":true,"server_now":"2026-10-18T00:00:00Z","shares":[{"id":"share-id","item_count":2,"max_viewers":2,"views_used":1,"expires_at":"2099-01-01T00:00:00Z"}]}"#.utf8)
        let listed = try await CatalogueShareAPI.fetchShares()
        precondition(Reply.request?.httpMethod == "GET" && listed.first?.url == nil && listed.first?.canRevoke == true)
        Reply.body = Data(#"{"ok":true}"#.utf8)
        try await CatalogueShareAPI.revokeShare(id: "share-id")
        precondition(Reply.request?.url?.path == "/api/catalogue-shares/share-id/revoke" && Reply.request?.httpMethod == "POST")
        precondition(String(decoding: Reply.requestBody, as: UTF8.self) == "{}")
        for (status, response, expected) in [
            (403, #"{"ok":false,"message":"Server refusal verbatim."}"#, "Server refusal verbatim."),
            (404, "<!DOCTYPE html><html>missing</html>", CatalogueShareError.notDeployed.localizedDescription),
            (404, #"{"ok":false}"#, CatalogueShareError.unavailable.localizedDescription),
            (503, "bad gateway", CatalogueShareError.unavailable.localizedDescription),
            (200, "bad json", CatalogueShareError.unavailable.localizedDescription)
        ] {
            Reply.status = status; Reply.body = Data(response.utf8)
            do { _ = try await CatalogueShareAPI.fetchShares(); preconditionFailure("Bad response accepted") }
            catch { precondition(error.localizedDescription == expected) }
        }
        Reply.status = 201
        Reply.body = Data(#"{"id":"bad","item_count":1,"max_viewers":1,"views_used":0,"expires_at":"2099-01-01T00:00:00Z","link_path":"https://evil.test"}"#.utf8)
        do { _ = try await CatalogueShareAPI.createShare(productIDs: ["first"], viewers: 1, minutes: 60, title: nil); preconditionFailure("Invalid created URL accepted") }
        catch { precondition(error.localizedDescription == CatalogueShareError.invalidLink.localizedDescription) }
        print("PASS: selection, cap, order, copy, link validation, date/status precedence, revoke without URL, API JSON/auth, list/revoke, error passthrough/fallbacks")
    }
}
