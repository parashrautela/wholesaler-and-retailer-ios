import SwiftUI
import UIKit

/// Hosts SwiftUI content inside a `UITextField`'s secure-entry canvas — the one
/// surface iOS deliberately omits from screenshots, screen recordings and the
/// app-switcher snapshot.
///
/// ## Why this shape, and not an API
///
/// iOS ships no equivalent of Android's `FLAG_SECURE`: there is no public call
/// that marks a view un-capturable, and `userDidTakeScreenshotNotification`
/// fires *after* the framebuffer has already been written to Photos, so
/// reacting to it cannot un-take the screenshot. The only mechanism that
/// redacts pixels at capture time is the one built for password fields, and the
/// only way to reach it is to re-parent content into the private view a secure
/// `UITextField` renders into.
///
/// ## Reaching the canvas — the part that has to be exactly right
///
/// The first attempt at this read `field.subviews.first` and left the canvas
/// where it was, inside the field. That renders correctly and redacts nothing:
/// verified on TestFlight, where screenshots came back with the design fully
/// visible. What the working implementations do instead is reach the canvas
/// through its *layer delegate* and lift it **out** of the text field into a
/// container of our own. Being re-parented is what carries the exclusion with
/// it; sitting inside a field that is never first responder does not.
///
/// The field itself is retained for the lifetime of the controller even though
/// it is never in the hierarchy. Letting it deallocate takes the canvas's
/// behaviour with it.
///
/// ## The failure mode this is designed around
///
/// None of this is API. The class, the layer ordering and the delegate
/// relationship have all changed across iOS releases and can change again with
/// no warning and no compile error — the lookup simply returns nothing one day.
///
/// So the contract is **fail open**: when the canvas cannot be found the
/// content renders normally and unprotected. A design that can be screenshotted
/// is a bad day. A catalogue of blank rectangles for every wholesaler on the
/// build is a much worse one, and that is what failing closed would ship.
/// `isProtected` reports which path was taken, and DEBUG builds trip an
/// assertion so a regression is loud here and quiet in production.
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

    /// Never added to the view hierarchy, but retained: the canvas we lift out
    /// of it stops behaving as a secure surface if the field it came from is
    /// deallocated.
    private let secureField = UITextField()

    /// `false` when the canvas could not be found and the content is therefore
    /// rendering unprotected.
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
        addChild(hosting)

        if let canvas = extractSecureCanvas() {
            isProtected = true
            view.addSubview(canvas)
            Self.pin(canvas, to: view)
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

    /// Lifts the capture-excluded canvas out of `secureField` so our content
    /// can be hosted inside it.
    ///
    /// Reached through `layer.sublayers.first.delegate` rather than
    /// `subviews.first`. Both name the same object today, but the layer-delegate
    /// route is the one that survives the field never becoming first
    /// responder — and re-parenting it into our own view is what actually
    /// carries the capture exclusion to the content.
    private func extractSecureCanvas() -> UIView? {
        secureField.isSecureTextEntry = true

        guard let canvas = secureField.layer.sublayers?.first?.delegate as? UIView else {
            return nil
        }

        // The canvas arrives carrying the field's own text-rendering subviews.
        // They are not ours and would draw over the content.
        canvas.subviews.forEach { $0.removeFromSuperview() }

        // Lifted out of the field and pinned by us, so it needs its own
        // constraints — unlike the previous attempt, which left it in the
        // field and had no business disabling autoresizing at all.
        canvas.removeFromSuperview()
        canvas.translatesAutoresizingMaskIntoConstraints = false
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
