import SwiftUI
import UIKit

/// Hosts SwiftUI content inside a `UITextField`'s secure-entry canvas — the one
/// surface iOS deliberately omits from screenshots, screen recordings and the
/// app-switcher snapshot.
///
/// ## Why this shape, and not an API
///
/// iOS ships no equivalent of Android's `FLAG_SECURE`: there is no public call
/// that marks a view as un-capturable, and `userDidTakeScreenshotNotification`
/// fires *after* the framebuffer has already been written to Photos, so
/// reacting to it cannot un-take the screenshot. The only mechanism that
/// actually redacts pixels at capture time is the one built for password
/// fields, and the only way to reach it is to re-parent content into the
/// private view a secure `UITextField` renders into.
///
/// ## The failure mode this is designed around
///
/// That view is not API. Its class and its position in the field's subviews
/// have both changed across iOS releases and can change again with no warning
/// and no compile error — the lookup simply returns nothing one day.
///
/// So the contract here is **fail open**: when the canvas cannot be found the
/// content renders normally and unprotected. A design that can be screenshotted
/// is a bad day. A catalogue that renders as blank rectangles for every
/// wholesaler on the build is a much worse one, and that is what failing closed
/// would ship. `isProtected` reports which path was taken, and DEBUG builds
/// trip an assertion so a regression is loud here and quiet in production.
struct SecureLayerHost<Content: View>: UIViewControllerRepresentable {

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> SecureHostController<Content> {
        SecureHostController(rootView: content)
    }

    func updateUIViewController(_ controller: SecureHostController<Content>, context: Context) {
        controller.update(rootView: content)
    }

    /// Answers with the proposal wherever the proposal is concrete, and only
    /// measures the content for a dimension SwiftUI left open.
    ///
    /// Forwarding wholesale to `UIHostingController.sizeThatFits` does not
    /// work: content framed `maxWidth: .infinity` has no preferred width to
    /// report, the measurement degenerates, and the view renders as a narrow
    /// strip. Omitting the method entirely is worse — the controller's plain
    /// root view has no intrinsic size, so the whole thing collapses to
    /// nothing. Taking the concrete half of the proposal is what actually
    /// holds, and it is well defined because call sites apply
    /// `.captureProtected()` AFTER the frame modifiers that size the content.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController controller: SecureHostController<Content>,
        context: Context
    ) -> CGSize? {
        let measured = controller.measure(proposal)
        return CGSize(
            width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? measured.width,
            height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? measured.height
        )
    }
}

/// The UIKit half of `SecureLayerHost`.
final class SecureHostController<Content: View>: UIViewController {

    private let hosting: UIHostingController<Content>

    /// `false` when the secure canvas could not be found and the content is
    /// therefore rendering unprotected. Surfaced so a caller can decide to warn
    /// rather than silently promise protection it is not getting.
    private(set) var isProtected = false

    init(rootView: Content) {
        hosting = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosting)

        if let canvas = Self.makeSecureCanvas(in: view) {
            isProtected = true
            canvas.addSubview(hosting.view)
            Self.pin(hosting.view, to: canvas)
        } else {
            isProtected = false
            assertionFailure(
                """
                SecureLayerHost: the secure text canvas was not found, so this \
                content is NOT capture-protected. iOS most likely changed the \
                private hierarchy behind `isSecureTextEntry`. Rendering \
                unprotected rather than blank — see the type doc.
                """
            )
            view.addSubview(hosting.view)
            Self.pin(hosting.view, to: view)
        }

        hosting.didMove(toParent: self)
    }

    func update(rootView: Content) {
        hosting.rootView = rootView
    }

    /// Content's own preferred size, used only to fill in a dimension the
    /// proposal left unspecified.
    func measure(_ proposal: ProposedViewSize) -> CGSize {
        hosting.sizeThatFits(in: proposal.replacingUnspecifiedDimensions())
    }

    // MARK: - The technique

    /// Installs a secure `UITextField` into `container` and returns the private
    /// subview it renders into, which is the surface iOS excludes from captures.
    ///
    /// The field itself is added to the hierarchy first: the canvas subview is
    /// created as part of the field's own layout, so reading `subviews` on a
    /// detached field returns an empty array and the technique silently does
    /// nothing.
    private static func makeSecureCanvas(in container: UIView) -> UIView? {
        let field = UITextField()
        field.isSecureTextEntry = true
        // The field is a rendering substrate, never an input: leaving it
        // interactive lets a tap summon a keyboard over the catalogue.
        field.isUserInteractionEnabled = false
        field.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(field)
        pin(field, to: container)
        container.layoutIfNeeded()

        guard let canvas = field.subviews.first else { return nil }

        // The canvas arrives carrying the field's own text-rendering subviews.
        // They are not ours and would draw over the content.
        canvas.subviews.forEach { $0.removeFromSuperview() }

        // Deliberately NOT setting `translatesAutoresizingMaskIntoConstraints`
        // here. The canvas belongs to the text field and the field positions it
        // itself; turning that off without supplying replacement constraints
        // leaves it with undefined geometry, which collapses everything hosted
        // inside it. The field is pinned to the container above, the canvas
        // fills the field, so the size arrives on its own.
        canvas.isUserInteractionEnabled = true
        return canvas
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
