import Foundation
func share(_ path: String?) -> WishlistShare {
 WishlistShare(id: "test", maxViewers: 1, viewsUsed: 0, expiresAt: "2026-10-09T00:00:00Z", revokedAt: nil, linkPath: path)
}
let token = String(repeating: "b", count: 64)
let path = "/share/wishlist#" + token
assert(share(path).url?.absoluteString == "https://jewel-india-frontend-yws1.vercel.app" + path)
for invalid in [nil, "", "/share/wishlist", "/share/wishlist#abc", "//evil.example/share/wishlist#" + token, "https://evil.example" + path, path + "?other=1", path + "\n", "/different#" + token] {
 assert(share(invalid).url == nil)
}
assert(share(path).expiry != nil)
for error in [WishlistShareError.notDeployed, .invalidLink, .unavailable] { assert(!error.localizedDescription.isEmpty) }
print("PASS trusted-host link generation; missing, malformed and external links rejected; dates and sharing errors decoded")
