import SwiftUI
import UIKit

/// A remote image rendered inside a secure `UITextField` canvas using a plain
/// `UIImageView` — no SwiftUI hosted anywhere inside the protected surface.
///
/// ## Why this exists alongside `captureProtected`
///
/// Two attempts at the generic modifier reached the canvas correctly and still
/// redacted nothing on hardware. What both had in common was a
/// `UIHostingController` inside the secure view. Every working implementation
/// of this technique hosts UIKit views; SwiftUI content composited by a
/// hosting controller appears not to inherit the render-server exclusion, so
/// the canvas is protected and the content drawn into it simply is not.
///
/// Everything worth protecting here is a photograph, so it does not need to be
/// SwiftUI on the inside. This puts a `UIImageView` — and nothing else —
/// inside the canvas.
///
/// Fails open like the modifier does: no canvas means the image still renders,
/// unprotected, rather than the catalogue going blank.
struct ProtectedImageView: UIViewRepresentable {

    let url: URL?
    var contentMode: UIView.ContentMode = .scaleAspectFill
    /// Longest edge to decode to, in pixels. Nil measures the view itself,
    /// which is what a grid of cards wants; pass a value for a view whose
    /// size isn't its display size (a zoomable canvas, say).
    var maxPixels: Int?

    func makeUIView(context: Context) -> SecureImageContainer {
        let container = SecureImageContainer()
        container.configure(contentMode: contentMode)
        container.load(url, maxPixels: maxPixels)
        return container
    }

    func updateUIView(_ container: SecureImageContainer, context: Context) {
        container.configure(contentMode: contentMode)
        container.load(url, maxPixels: maxPixels)
    }
}

/// Holds the secure canvas and the single `UIImageView` inside it.
final class SecureImageContainer: UIView {

    /// Never enters the hierarchy, but retained: the canvas stops behaving as
    /// a secure surface once the field it came from is deallocated.
    private let secureField = UITextField()
    private let imageView = UIImageView()
    private var loadedURL: URL?
    private var requestedPixels: Int?
    private var pixelsOverride: Int?
    private var task: Task<Void, Never>?

    private(set) var isProtected = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        // These sit inside SwiftUI `Button` labels (gallery cards, the picker
        // grid). A UIView that accepts touches but handles none of them wins
        // the hit-test and swallows the tap, so the card stops responding —
        // the same class of bug as the image overflow, arrived at from the
        // other direction. Nothing in here is interactive; let taps through.
        isUserInteractionEnabled = false
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        secureField.isSecureTextEntry = true

        if let canvas = secureField.layer.sublayers?.first?.delegate as? UIView {
            isProtected = true
            canvas.subviews.forEach { $0.removeFromSuperview() }
            canvas.removeFromSuperview()
            canvas.translatesAutoresizingMaskIntoConstraints = false
            canvas.isUserInteractionEnabled = false
            addSubview(canvas)
            Self.pin(canvas, to: self)
            canvas.addSubview(imageView)
            Self.pin(imageView, to: canvas)
        } else {
            isProtected = false
            assertionFailure("ProtectedImageView: no secure canvas — image renders UNPROTECTED.")
            addSubview(imageView)
            Self.pin(imageView, to: self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { task?.cancel() }

    func configure(contentMode mode: UIView.ContentMode) {
        imageView.contentMode = mode
    }

    /// Goes through `ImageCache`, which downloads once, decodes no larger than
    /// this view draws, and keeps the result in memory and on disk.
    /// `AsyncImage` cannot be used here — it is SwiftUI, which is the thing
    /// this type exists to keep out of the canvas.
    func load(_ url: URL?, maxPixels: Int?) {
        pixelsOverride = maxPixels
        let wanted = maxPixels ?? pixelsForBounds()

        // Re-decode only when the view has grown enough to show more detail —
        // a few points of layout drift must not restart the download.
        let alreadyGood = imageView.image != nil
            && url == loadedURL
            && (requestedPixels ?? 0) >= wanted
        guard !alreadyGood else { return }

        if url != loadedURL {
            imageView.image = nil
        }
        loadedURL = url
        requestedPixels = wanted
        task?.cancel()

        guard let url else { return }

        task = Task { [weak self] in
            let image = try? await ImageCache.shared.image(for: url, maxPixels: wanted).value
            guard let self, let image, !Task.isCancelled, self.loadedURL == url else { return }
            self.imageView.image = image
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The first layout is when the real size is known; a view laid out
        // bigger than it was decoded for gets a sharper copy.
        if pixelsOverride == nil, let url = loadedURL, pixelsForBounds() > (requestedPixels ?? 0) {
            load(url, maxPixels: nil)
        }
    }

    /// The view's longest edge in device pixels, in coarse steps so a grid of
    /// slightly different cards shares one cached decode. Zero bounds (before
    /// the first layout) fall back to a card-sized decode.
    private func pixelsForBounds() -> Int {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let longest = max(bounds.width, bounds.height) * scale
        guard longest > 1 else { return 540 }
        for step in [270, 540, 1080, 1600, 2048] where Double(step) >= longest {
            return step
        }
        return 2560
    }

    private static func pin(_ child: UIView, to parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
        ])
    }
}
