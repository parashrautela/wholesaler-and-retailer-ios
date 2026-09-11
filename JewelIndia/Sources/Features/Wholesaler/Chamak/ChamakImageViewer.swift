import SwiftUI

/// One image the full-screen viewer can show.
struct ChamakViewerImage: Identifiable, Hashable {
    let id: String
    let label: String
    let url: URL
    /// The generated output, as opposed to one of the designs that went in.
    /// Compare always pins the result to one pane.
    let isResult: Bool
}

/// Drives `fullScreenCover(item:)` — which images, and which one to open on.
struct ChamakViewerRequest: Identifiable {
    let id = UUID()
    let images: [ChamakViewerImage]
    let startIndex: Int
}

/// Full-screen, zoomable view of a Chamak result and the designs it came from.
///
/// Two modes:
/// - **Browse** — one image at a time. Swipe sideways or tap a thumbnail to
///   switch, pinch or double-tap to zoom, swipe down to close.
/// - **Compare** — the result and one source split the screen (stacked on a
///   phone, side by side when there's width), each zoomable on its own. The
///   thumbnails pick which source sits against the result.
///
/// Compare is a split rather than a before/after wipe on purpose: the output
/// is a new render, not an edit of either source, so nothing lines up pixel
/// for pixel and a wipe slider would only show two unrelated halves.
///
/// Every image is a `ProtectedImageView`, so the viewer is as screenshot-proof
/// as the rest of the designs in the app.
struct ChamakImageViewer: View {
    let images: [ChamakViewerImage]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selection: Int
    @State private var isComparing = false
    @State private var compareIndex: Int
    @State private var isZoomed = false
    @State private var dragOffset: CGSize = .zero
    /// Set when a pinch starts and held briefly after it ends. Two moving
    /// fingers also look like a drag, and without this a spread to zoom was
    /// read as a swipe and paged to the next image instead.
    @State private var didPinch = false

    init(images: [ChamakViewerImage], startIndex: Int) {
        self.images = images
        _selection = State(initialValue: images.indices.contains(startIndex) ? startIndex : 0)
        _compareIndex = State(initialValue: images.firstIndex { !$0.isResult } ?? 0)
    }

    private var resultIndex: Int? { images.firstIndex(where: \.isResult) }

    private var canCompare: Bool {
        resultIndex != nil && images.contains { !$0.isResult }
    }

    /// Fades the backdrop as the image is dragged down, so the dismiss
    /// gesture reads as "putting the photo away".
    private var backdropOpacity: Double {
        1 - min(max(dragOffset.height, 0) / 500, 0.6)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            if images.isEmpty {
                closeButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Spacing.base)
            } else {
                VStack(spacing: 0) {
                    topBar
                    Group {
                        if isComparing, let resultIndex {
                            compareContent(resultIndex: resultIndex)
                        } else {
                            browseContent
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    thumbnailStrip
                }
            }
        }
        .statusBarHidden()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        ZStack {
            Text(isComparing ? "Compare" : images[selection].label)
                .font(.manrope(15, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.opacity)

            HStack {
                closeButton
                Spacer()
                if canCompare {
                    Button {
                        withAnimation(.snappy) { isComparing.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isComparing ? "square" : "rectangle.split.1x2")
                            Text(isComparing ? "Single" : "Compare")
                        }
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(isComparing ? Palette.dark : .white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(
                            isComparing ? Color(hex: 0xE4CC8F) : .white.opacity(0.15),
                            in: .capsule
                        )
                    }
                    .accessibilityLabel(isComparing ? "Show one image" : "Compare with a source design")
                }
            }
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.sm)
        .opacity(backdropOpacity)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.15), in: .circle)
        }
        .accessibilityLabel("Close")
    }

    // MARK: - Browse

    private var browseContent: some View {
        ZoomableProtectedImage(
            url: images[selection].url,
            onZoomChange: { isZoomed = $0 },
            onPinchChange: { pinching in
                if pinching {
                    didPinch = true
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = .zero }
                } else {
                    // Outlive the drag's own onEnded, which fires as the same
                    // fingers lift.
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        didPinch = false
                    }
                }
            }
        )
        .id(images[selection].id)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .offset(x: dragOffset.width * 0.35, y: max(dragOffset.height, 0))
        .contentShape(.rect)
        // While zoomed, drags belong to the image (panning). Otherwise a
        // sideways drag pages and a downward one dismisses. Simultaneous, so
        // the image's pinch is never starved by this.
        .simultaneousGesture(browseDrag, including: isZoomed ? .subviews : .all)
    }

    private var browseDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard !didPinch else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height

                guard !didPinch, !isZoomed else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = .zero }
                    return
                }

                if dy > 120, abs(dy) > abs(dx) {
                    dismiss()
                    return
                }
                if abs(dx) > 60, abs(dx) > abs(dy) {
                    show(selection + (dx < 0 ? 1 : -1))
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    dragOffset = .zero
                }
            }
    }

    private func show(_ index: Int) {
        guard images.indices.contains(index), index != selection else { return }
        isZoomed = false
        withAnimation(.easeInOut(duration: 0.2)) {
            selection = index
        }
    }

    // MARK: - Compare

    private func compareContent(resultIndex: Int) -> some View {
        GeometryReader { geo in
            let sideBySide = horizontalSizeClass == .regular || geo.size.width > geo.size.height
            let layout = sideBySide
                ? AnyLayout(HStackLayout(spacing: 2))
                : AnyLayout(VStackLayout(spacing: 2))

            layout {
                comparePane(images[resultIndex])
                comparePane(images[compareIndex])
            }
        }
    }

    private func comparePane(_ image: ChamakViewerImage) -> some View {
        ZoomableProtectedImage(url: image.url)
            .id(image.id)
            .overlay(alignment: .topLeading) {
                Text(image.label)
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(image.isResult ? Palette.dark : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        image.isResult ? Color(hex: 0xE4CC8F) : .black.opacity(0.55),
                        in: .capsule
                    )
                    .padding(Spacing.sm)
                    .allowsHitTesting(false)
            }
            .background(Color.white.opacity(0.04))
    }

    // MARK: - Thumbnails

    private var thumbnailStrip: some View {
        VStack(spacing: Spacing.sm) {
            if isComparing {
                Text("Tap a design to compare it with the result")
                    .font(.manrope(11))
                    .foregroundStyle(.white.opacity(0.6))
            }

            HStack(spacing: Spacing.md) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    thumbnail(image, index: index)
                }
            }
        }
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.base)
        .opacity(backdropOpacity)
    }

    private func thumbnail(_ image: ChamakViewerImage, index: Int) -> some View {
        let isSelected = isComparing ? index == compareIndex : index == selection
        // In Compare the result is already pinned to a pane, so only the
        // designs are choosable.
        let isEnabled = !isComparing || !image.isResult

        return Button {
            if isComparing {
                withAnimation(.easeInOut(duration: 0.2)) { compareIndex = index }
            } else {
                show(index)
            }
        } label: {
            VStack(spacing: 6) {
                Color.white.opacity(0.08)
                    .frame(width: 64, height: 64)
                    .overlay { ProtectedImageView(url: image.url) }
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected ? Color(hex: 0xE4CC8F) : .white.opacity(0.2),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }

                Text(image.label)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(image.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Zoomable Image

/// A protected image that pinches and double-taps to zoom (up to 4×) and pans
/// while zoomed. Panning is clamped so the photo can't be dragged off-screen.
struct ZoomableProtectedImage: View {
    let url: URL
    var onZoomChange: (Bool) -> Void = { _ in }
    var onPinchChange: (Bool) -> Void = { _ in }

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var isPinching = false

    private let maxScale: CGFloat = 4
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            ProtectedImageView(url: url, contentMode: .scaleAspectFit)
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .contentShape(.rect)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        if scale > 1 {
                            reset()
                        } else {
                            scale = doubleTapScale
                            baseScale = doubleTapScale
                        }
                    }
                }
                .gesture(magnify(in: geo.size))
                .simultaneousGesture(pan(in: geo.size), including: scale > 1 ? .all : .none)
        }
        .clipped()
        .onChange(of: scale > 1) { _, zoomed in
            onZoomChange(zoomed)
        }
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    onPinchChange(true)
                }
                scale = min(max(baseScale * value.magnification, 1), maxScale)
                offset = clamped(offset, in: size)
            }
            .onEnded { _ in
                isPinching = false
                onPinchChange(false)
                if scale <= 1.01 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { reset() }
                } else {
                    baseScale = scale
                    offset = clamped(offset, in: size)
                    baseOffset = offset
                }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(
                    CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height
                    ),
                    in: size
                )
            }
            .onEnded { _ in
                baseOffset = offset
            }
    }

    private func reset() {
        scale = 1
        baseScale = 1
        offset = .zero
        baseOffset = .zero
    }

    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}
