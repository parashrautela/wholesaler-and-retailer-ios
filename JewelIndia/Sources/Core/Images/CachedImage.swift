import SwiftUI

/// A remote image that goes through `ImageCache`: downloaded once, decoded no
/// larger than it is drawn, kept in memory and on disk.
///
/// `ProtectedImageView` is the equivalent for anything a wholesaler's camera
/// produced — it adds the screenshot-proof canvas. This one is for artwork we
/// ship or host ourselves, where that protection means nothing and a plain
/// image view keeps the code (and the screenshots) simple.
struct CachedImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Palette.taupe.opacity(0.35)
                }
            }
            .task(id: url) { await load(width: geometry.size.width) }
        }
    }

    private func load(width: CGFloat) async {
        guard let url, image == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let pixels = Int(max(width, 1) * (UIScreen.main.scale))
        image = try? await ImageCache.shared.image(for: url, maxPixels: max(pixels, 320)).value
    }
}
