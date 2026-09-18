import SwiftUI

// Shared pieces of the employee view's full-screen detail pages, ported from
// `components/employee/ProductInfoModal.jsx` and
// `components/shared/FullImageViewer.jsx`.

/// CSS `clamp(min, vw × width, max)`.
func cssClamp(_ minimum: CGFloat, _ viewportFraction: CGFloat, _ maximum: CGFloat, width: CGFloat) -> CGFloat {
    min(max(minimum, viewportFraction * width), maximum)
}

/// `formatWeight` — whole grams without decimals, otherwise two places.
func formatGrams(_ value: Double?) -> String? {
    guard let value, value.isFinite else { return nil }
    if value.rounded() == value { return "\(Int(value))g" }
    return String(format: "%.2fg", value)
}

// MARK: - Glass circle

/// The frosted round button the web uses for Back and Zoom.
struct GlassCircleButton: View {
    let systemImage: String
    var size: CGFloat = 48
    var iconSize: CGFloat = 22
    var weight: Font.Weight = .regular
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize * 0.82, weight: weight))
                .foregroundStyle(.black)
                .frame(width: size, height: size)
                .background {
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.43), location: 0.178),
                                    .init(color: Color(hex: 0xE0E0E0).opacity(0.43), location: 0.904)
                                ],
                                startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1)
                            )
                        )
                        // The web's two inset shadows: dark lower-right, light upper-left.
                        Circle().stroke(
                            LinearGradient(colors: [.white.opacity(0.25), .black.opacity(0.25)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 2
                        )
                        .blur(radius: 1.5)
                        .clipShape(Circle())
                    }
                }
                .overlay { Circle().stroke(Color(hex: 0x696969), lineWidth: 0.436) }
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 1.7, y: 2.2)
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .accessibilityLabel(label)
    }
}

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Themed background

/// Behind a full-screen design: the claimed theme's arch artwork over white.
struct ThemedDetailBackground: View {
    let theme: EmployeeTheme

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack(alignment: .top) {
                Color.white
                switch (theme, landscape) {
                case (.indian, false):
                    // `background-size: 100% 100%` — stretched, not cropped.
                    StretchedArt(url: theme.detailBackground(landscape: false))
                        .frame(width: geo.size.width, height: geo.size.height)
                default:
                    CachedImage(url: theme.detailBackground(landscape: landscape))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// An image drawn to exactly fill its frame, ignoring aspect ratio.
private struct StretchedArt: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = try? await ImageCache.shared.image(for: url, maxPixels: 1600).value
        }
    }
}

// MARK: - Specification sections

/// A heading with a dashed rule running to the edge, then its rows.
struct DetailSpecSection<Rows: View>: View {
    let title: String
    let width: CGFloat
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(title.uppercased())
                    .font(.manrope(cssClamp(10, 0.015, 12, width: width), weight: .bold))
                    .kerning(cssClamp(10, 0.015, 12, width: width) * 0.2)
                    .foregroundStyle(.black)
                DashedRule()
            }
            .padding(.bottom, 8)
            rows
        }
    }
}

struct DetailSpecRow: View {
    let label: String
    let value: String
    let width: CGFloat

    var body: some View {
        let size = cssClamp(13, 0.018, 15, width: width)
        HStack {
            Text(label)
                .font(.manrope(size, weight: .medium))
                .foregroundStyle(Color(hex: 0x6E6E6E))
            Spacer(minLength: 8)
            Text(value)
                .font(.manrope(size, weight: .semibold))
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 4)
    }
}

private struct DashedRule: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(Color(hex: 0xA8A8A8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(height: 1)
    }
}

// MARK: - Design detail

/// A store's own design, full screen (`ProductInfoModal` with
/// `isFullScreen`). Opened from Home and from Designs. It has no request or
/// chat buttons — on the web those only appear when a chat handler is
/// passed, which these screens never do.
struct EmployeeDesignDetail: View {
    let design: RetailerDesign
    let theme: EmployeeTheme
    let onClose: () -> Void

    @State private var width: CGFloat = 390
    @State private var viewerOpen = false

    private var title: String {
        design.title?.trimmed.nilIfEmpty
            ?? design.type?.trimmed.nilIfEmpty?.capitalized
            ?? "Untitled Product"
    }

    private var category: String {
        design.category?.trimmed.nilIfEmpty ?? design.type?.trimmed.nilIfEmpty ?? "Uncategorized"
    }

    private var leadTime: String? {
        guard let days = design.productionTimeDays, days > 0 else { return nil }
        return "\(days) to \(days + 2) days"
    }

    var body: some View {
        ZStack(alignment: .top) {
            ThemedDetailBackground(theme: theme)

            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) {
                        GlassCircleButton(systemImage: "arrow.left", label: "Go back", action: onClose)
                            .padding(.leading, width >= 768 ? 40 : 24)
                            .padding(.top, 40)
                    }
                    .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .fullScreenCover(isPresented: $viewerOpen) {
            if let url = design.imageLink {
                JewelFullImageViewer(urls: [url], startIndex: 0) { viewerOpen = false }
                    .presentationBackground(.clear)
            }
        }
    }

    private var content: some View {
        let columnWidth: CGFloat = width >= 1024 ? 700 : width >= 768 ? 600 : width >= 640 ? 500 : 400
        let edge = cssClamp(20, 0.05, 40, width: width)

        return VStack(spacing: 0) {
            header
                .padding(.bottom, 40)
            imageBox
                .padding(.bottom, 48)
            specs(columnWidth: columnWidth - edge * 2)
                .padding(.top, 16)
        }
        .frame(maxWidth: columnWidth)
        .padding(.top, cssClamp(90, 0.10, 115, width: width))
        .padding(.horizontal, edge)
        .padding(.bottom, edge)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                let size = cssClamp(12, 0.018, 16, width: width)
                Text(category.uppercased())
                    .font(.manrope(size, weight: .bold))
                    .kerning(size * 0.2)
                    .foregroundStyle(Color(hex: 0x6E6E6E))
                if let style = design.styleAesthetic?.trimmed.nilIfEmpty {
                    let chip = cssClamp(10, 0.015, 12, width: width)
                    Text(style)
                        .font(.manrope(chip, weight: .medium))
                        .kerning(chip * 0.02)
                        .foregroundStyle(Color(hex: 0x515151))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xA8A8A8), lineWidth: 1)
                        }
                }
            }
            let titleSize = cssClamp(24, 0.04, 38, width: width)
            Text(title)
                .font(.gilda(titleSize))
                .kerning(titleSize * 0.025)
                .lineSpacing(titleSize * 0.2)
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
        }
    }

    private var imageBox: some View {
        let maxWidth: CGFloat = width >= 768 ? 320 : width >= 640 ? 280 : 240
        let buttonSize: CGFloat = width >= 640 ? 48 : 40

        return Button { if design.imageLink != nil { viewerOpen = true } } label: {
            Color(hex: 0xF5F5F5)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    if let url = design.imageLink {
                        ProtectedImageView(url: url, contentMode: .scaleAspectFit, watermark: true, multiply: true)
                    } else {
                        Text("No image")
                            .font(.manrope(14, weight: .light))
                            .foregroundStyle(Color(hex: 0xD1D5DC))
                    }
                }
                .clipShape(.rect(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xF3F4F6).opacity(0.6), lineWidth: 1) }
                .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: maxWidth)
        .overlay(alignment: .bottomTrailing) {
            if design.imageLink != nil {
                GlassCircleButton(systemImage: "arrow.up.left.and.arrow.down.right",
                                  size: buttonSize, iconSize: 18, weight: .semibold,
                                  label: "Zoom image") { viewerOpen = true }
                    .padding(12)
            }
        }
    }

    @ViewBuilder
    private func specs(columnWidth: CGFloat) -> some View {
        let twoColumns = width >= 640
        let columnSize: CGFloat = width >= 1024 ? 290 : width >= 768 ? 250 : 210

        let left = VStack(alignment: .leading, spacing: 24) {
            if let purity = design.purity?.trimmed.nilIfEmpty {
                DetailSpecSection(title: "Material", width: width) {
                    DetailSpecRow(label: "Gold", value: purity, width: width)
                }
            }
            let weights: [(String, String)] = [
                ("Net weight", formatGrams(design.netWeight)),
                ("Gross weight", formatGrams(design.grossWeight)),
                ("Stone weight", formatGrams(design.stoneWeight))
            ].compactMap { label, value in value.map { (label, $0) } }
            if !weights.isEmpty {
                DetailSpecSection(title: "Weight", width: width) {
                    VStack(spacing: 8) {
                        ForEach(weights, id: \.0) { DetailSpecRow(label: $0.0, value: $0.1, width: width) }
                    }
                }
            }
        }

        let right = VStack(alignment: .leading, spacing: 24) {
            if let inStock = design.isInStock {
                DetailSpecSection(title: "Availability", width: width) {
                    DetailSpecRow(label: inStock ? "In stock" : "Made to order",
                                  value: inStock ? "" : (leadTime ?? ""), width: width)
                }
            }
        }

        if twoColumns {
            HStack(alignment: .top) {
                left.frame(width: columnSize, alignment: .leading)
                Spacer(minLength: 0)
                right.frame(width: columnSize, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 32) {
                left
                right
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Full image viewer

/// `FullImageViewer`: the image on near-black, pinch to zoom, swipe or
/// chevrons between images, thumbnails along the bottom.
struct JewelFullImageViewer: View {
    let urls: [URL]
    let onIndexChange: ((Int) -> Void)?
    let onClose: () -> Void

    @State private var index: Int
    @State private var zoomed = false

    init(urls: [URL], startIndex: Int, onIndexChange: ((Int) -> Void)? = nil, onClose: @escaping () -> Void) {
        self.urls = urls
        self.onIndexChange = onIndexChange
        self.onClose = onClose
        _index = State(initialValue: min(max(startIndex, 0), max(urls.count - 1, 0)))
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 768
            ZStack {
                Color.black.opacity(0.95)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)

                if urls.indices.contains(index) {
                    ZoomableProtectedImage(url: urls[index], onZoomChange: { zoomed = $0 })
                        .id(urls[index])
                        .frame(maxWidth: geo.size.width * 0.9,
                               maxHeight: geo.size.height * (wide ? 0.88 : 0.85))
                        .gesture(swipe, including: zoomed ? .subviews : .all)
                } else {
                    Text("Loading Premium Design...")
                        .font(.manrope(14))
                        .foregroundStyle(.white.opacity(0.6))
                }

                if urls.count > 1 {
                    HStack {
                        chevron("chevron.left") { step(-1) }
                        Spacer()
                        chevron("chevron.right") { step(1) }
                    }
                    .padding(.horizontal, wide ? 40 : 24)
                }
            }
            .overlay(alignment: .top) { header }
            .overlay(alignment: .bottom) { if urls.count > 1 { thumbnails } }
        }
        .onChange(of: index) { _, value in onIndexChange?(value) }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.left").font(.system(size: 15, weight: .semibold))
                    Text("Back").font(.manrope(14, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.white.opacity(0.1), in: Capsule())
                .background(.ultraThinMaterial.opacity(0.4), in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.1), lineWidth: 1) }
                .shadow(color: .black.opacity(0.1), radius: 7, y: 5)
            }
            .buttonStyle(PressScaleStyle())
            Spacer()
            if urls.count > 1 {
                Text("\(index + 1) / \(urls.count)")
                    .font(.manrope(13))
                    .kerning(0.65)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.05), in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.05), lineWidth: 1) }
            }
        }
        .padding(24)
    }

    private func chevron(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.05), in: Circle())
                .background(.ultraThinMaterial.opacity(0.4), in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.1), lineWidth: 1) }
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
    }

    private var thumbnails: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(urls.enumerated()), id: \.offset) { offset, url in
                    Button { index = offset } label: {
                        ProtectedImageView(url: url, contentMode: .scaleAspectFill)
                            .frame(width: 72, height: 72)
                            .background(Color(hex: 0x222222))
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(offset == index ? Color.white : .clear, lineWidth: 2.5)
                            }
                            .scaleEffect(offset == index ? 1.05 : 1)
                            .opacity(offset == index ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .background(
            LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.4), .clear],
                           startPoint: .bottom, endPoint: .top)
        )
    }

    /// Only at 1×: a mostly-horizontal drag of more than 60pt changes image.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard !zoomed, urls.count > 1 else { return }
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 60, abs(dy) < 40 else { return }
                step(dx < 0 ? 1 : -1)
            }
    }

    /// Wraps at both ends, like the web.
    private func step(_ delta: Int) {
        guard !urls.isEmpty else { return }
        index = (index + delta + urls.count) % urls.count
    }
}
