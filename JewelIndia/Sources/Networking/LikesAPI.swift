import Foundation
import Observation
import Supabase
import SwiftUI

/// Hearts on wholesaler designs, shared by every screen that shows one, so a
/// design liked in a grid is filled in its detail page too — and for staff
/// and store owners alike. Wholesalers only ever see the counts, in their
/// report (`WholesalerReportAPI`).
@MainActor
@Observable
final class LikeBook {
    static let shared = LikeBook()

    private(set) var liked: Set<String> = []
    private var inFlight: Set<String> = []
    private var loadedAt: Date?

    private var db: SupabaseClient { SupabaseManager.client }

    func isLiked(_ productID: String) -> Bool { liked.contains(productID.lowercased()) }

    /// RLS returns only the caller's own likes. Cheap, so screens call it on
    /// appear; a fresh copy is reused for a minute.
    func load(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 60 { return }
        struct Row: Decodable { let product_id: String }
        guard let rows: [Row] = try? await db.from("product_likes")
            .select("product_id")
            .execute()
            .value
        else { return }
        liked = Set(rows.map { $0.product_id.lowercased() })
        loadedAt = Date()
    }

    /// Flips the heart at once and settles it with the server's answer.
    func toggle(_ productID: String) async {
        let id = productID.lowercased()
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }

        let wasLiked = liked.contains(id)
        if wasLiked { liked.remove(id) } else { liked.insert(id) }

        struct Reply: Decodable { let ok: Bool; let liked: Bool? }
        do {
            let reply: Reply = try await db
                .rpc("toggle_product_like", params: ["p_product": productID])
                .execute()
                .value
            guard reply.ok, let now = reply.liked else { throw URLError(.badServerResponse) }
            if now { liked.insert(id) } else { liked.remove(id) }
        } catch {
            if wasLiked { liked.insert(id) } else { liked.remove(id) }
        }
    }
}

/// A heart for a design. Draws from and writes to `LikeBook.shared`.

struct LikeButton: View {
    let productID: String
    var size: CGFloat = 17
    @State private var book = LikeBook.shared
    @State private var bump = false

    var body: some View {
        let liked = book.isLiked(productID)
        Button {
            bump.toggle()
            Task { await book.toggle(productID) }
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(liked ? Color(hex: 0xE11D48) : Palette.muted)
                .symbolEffect(.bounce, value: bump)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(liked ? "Unlike" : "Like")
        .accessibilityAddTraits(liked ? .isSelected : [])
    }
}
