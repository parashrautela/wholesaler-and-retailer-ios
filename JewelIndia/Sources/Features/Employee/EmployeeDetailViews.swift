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

/// A heart in the same frosted glass as Zoom. Filled rose when liked.
struct GlassLikeButton: View {
    @Environment(\.employeeAppearance) private var appearance
    let productID: String
    var size: CGFloat = 48
    @State private var book = LikeBook.shared
    @State private var bump = false

    var body: some View {
        let liked = book.isLiked(productID)
        GlassCircleButton(systemImage: liked ? "heart.fill" : "heart",
                          size: size, iconSize: 20, weight: .semibold,
                          tint: liked ? Color(hex: 0xE11D48) : .black,
                          label: liked ? "Unlike" : "Like") {
            bump.toggle()
            Task { await book.toggle(productID) }
        }
        .symbolEffect(.bounce, value: bump)
        .accessibilityAddTraits(liked ? .isSelected : [])
    }
}

/// The frosted round button the web uses for Back and Zoom.
struct GlassCircleButton: View {
    @Environment(\.employeeAppearance) private var appearance
    let systemImage: String
    var size: CGFloat = 48
    var iconSize: CGFloat = 22
    var weight: Font.Weight = .regular
    var tint: Color = .black
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize * 0.82, weight: weight))
                .foregroundStyle(appearance.enabled && tint == .black ? appearance.text : tint)
                .frame(width: size, height: size)
                .background {
                    if appearance.enabled { Circle().fill(appearance.surface) }
                    else {
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
                }
                .overlay { Circle().stroke(appearance.line(Color(hex: 0x696969)), lineWidth: 0.436) }
                .clipShape(Circle())
                .shadow(color: .black.opacity(appearance.enabled ? 0.04 : 0.25), radius: 1.7, y: 2.2)
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
    @Environment(\.employeeAppearance) private var appearance
    let theme: EmployeeTheme

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack(alignment: .top) {
                appearance.panel()
                if appearance.enabled {
                    LinearGradient(colors: [appearance.selected, appearance.background], startPoint: .top, endPoint: .center)
                } else {
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
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// An image drawn to exactly fill its frame, ignoring aspect ratio.
private struct StretchedArt: View {
    @Environment(\.employeeAppearance) private var appearance
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
    @Environment(\.employeeAppearance) private var appearance
    let title: String
    let width: CGFloat
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(title.uppercased())
                    .font(appearance.body(cssClamp(10, 0.015, 12, width: width), weight: .bold))
                    .kerning(cssClamp(10, 0.015, 12, width: width) * 0.2)
                    .foregroundStyle(appearance.ink(.black))
                DashedRule()
            }
            .padding(.bottom, 8)
            rows
        }
    }
}

struct DetailSpecRow: View {
    @Environment(\.employeeAppearance) private var appearance
    let label: String
    let value: String
    let width: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                labelText.fixedSize()
                Spacer(minLength: 8)
                valueText.fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                labelText
                valueText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }

    private var labelText: some View {
        Text(label).font(appearance.body(cssClamp(13, 0.018, 15, width: width), weight: .medium))
            .foregroundStyle(appearance.secondaryInk(Color(hex: 0x6E6E6E)))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value).font(appearance.body(cssClamp(13, 0.018, 15, width: width), weight: .semibold))
            .foregroundStyle(appearance.ink(.black))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DashedRule: View {
    @Environment(\.employeeAppearance) private var appearance
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(appearance.line(Color(hex: 0xA8A8A8)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(height: 1)
    }
}

// MARK: - Employee detail geometry

/// The proposed size already excludes safe areas and employee chrome. Keep the
/// media fixed while the information scrolls; photograph aspect ratio is handled
/// inside the media pane rather than changing the 2:1 tracks.
struct EmployeeDetailLayout<Media: View, Details: View>: View {
    @Environment(\.employeeAppearance) private var appearance
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var onClose: (() -> Void)? = nil
    @ViewBuilder var media: (CGSize) -> Media
    @ViewBuilder var details: (CGFloat) -> Details

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            // Accessibility sizes reserve more room for reading and actions.
            // This explicit exception does not shrink text or scroll the photo away.
            let mediaShare: CGFloat = dynamicTypeSize.isAccessibilitySize ? (wide ? 0.5 : 0.4) : 2.0 / 3.0
            let mediaSize = CGSize(width: wide ? geo.size.width * mediaShare : geo.size.width,
                                   height: wide ? geo.size.height : geo.size.height * mediaShare)
            let detailSize = CGSize(width: wide ? geo.size.width - mediaSize.width : geo.size.width,
                                    height: wide ? geo.size.height : geo.size.height - mediaSize.height)
            let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                media(mediaSize)
                    .frame(width: mediaSize.width, height: mediaSize.height)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        if let onClose {
                            GlassCircleButton(systemImage: "arrow.left", label: "Go back", action: onClose)
                                .padding(12)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("employee-detail-media")
                    #if DEBUG
                    .background {
                        if UserDefaults.standard.bool(forKey: "JewelEmployeeGeometry") {
                            EmployeeDetailRegionMarker(identifier: "employee-detail-media-bounds")
                                .allowsHitTesting(false)
                        }
                    }
                    #endif
                ScrollViewReader { scroll in
                  ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        details(max(0, detailSize.width - 40))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                        #if DEBUG
                        Color.clear.frame(height: 0).id("employee-detail-end")
                        #endif
                    }
                  }
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: detailSize.width, height: detailSize.height)
                .background(appearance.panel().opacity(0.97))
                .overlay(alignment: wide ? .leading : .top) {
                    Rectangle().fill(appearance.border)
                        .frame(width: wide ? 1 : nil, height: wide ? nil : 1)
                }
                .accessibilityIdentifier("employee-detail-content")
                  #if DEBUG
                  .background {
                      if UserDefaults.standard.bool(forKey: "JewelEmployeeGeometry") {
                          EmployeeDetailRegionMarker(identifier: "employee-detail-content-bounds")
                              .allowsHitTesting(false)
                      }
                  }
                  .task {
                      guard UserDefaults.standard.bool(forKey: "JewelEmployeeScrollBottom") else { return }
                      // Allow the real scroll view to lay out before a fixture scroll.
                      try? await Task.sleep(for: .milliseconds(200))
                      scroll.scrollTo("employee-detail-end", anchor: .bottom)
                  }
                  #endif
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            #if DEBUG
            .onGeometryChange(for: CGSize.self, of: \.size) { size in logGeometry(size) }
            .onChange(of: dynamicTypeSize) { _, _ in logGeometry(geo.size) }
            .onChange(of: appearance.style) { _, _ in logGeometry(geo.size) }
            #endif
        }
    }

    #if DEBUG
    private func logGeometry(_ size: CGSize) {
        guard UserDefaults.standard.bool(forKey: "JewelEmployeeGeometry") else { return }
        let wide = size.width > size.height
        let share: CGFloat = dynamicTypeSize.isAccessibilitySize ? (wide ? 0.5 : 0.4) : 2.0 / 3.0
        let media = CGRect(x: 0, y: 0, width: wide ? size.width * share : size.width,
                           height: wide ? size.height : size.height * share)
        let content = CGRect(x: wide ? media.width : 0, y: wide ? 0 : media.height,
                             width: wide ? size.width - media.width : size.width,
                             height: wide ? size.height : size.height - media.height)
        NSLog("EmployeeDetailGeometry %@", "style=\(appearance.style.rawValue) dynamicType=\(dynamicTypeSize) wide=\(wide) usable=\(size) media=\(media) content=\(content) imageShare=\(share)")
    }
    #endif
}

#if DEBUG
/// Clear, noninteractive UIKit markers expose actual track frames to XCUI.
/// UIKit identifiers avoid SwiftUI's identifier inheritance across descendants.
/// They exist only for an explicitly opted-in geometry verification launch.
private struct EmployeeDetailRegionMarker: UIViewRepresentable {
    let identifier: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityTraits = .staticText
        view.accessibilityLabel = identifier
        view.accessibilityIdentifier = identifier
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = identifier
    }
}
#endif

// MARK: - Design detail

/// A store's own design, full screen (`ProductInfoModal` with
/// `isFullScreen`). Opened from Home and from Designs. It has no request or
/// chat buttons — on the web those only appear when a chat handler is
/// passed, which these screens never do.
struct EmployeeDesignDetail: View {
    @Environment(\.employeeAppearance) private var appearance
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        EmployeeDetailLayout(onClose: onClose) { _ in
            imageBox.padding(12)
        } details: { contentWidth in
            VStack(alignment: .leading, spacing: 24) {
                header
                specs(columnWidth: contentWidth)
            }
        }
        .background { ThemedDetailBackground(theme: theme) }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .fullScreenCover(isPresented: $viewerOpen) {
            if let url = design.imageLink {
                JewelFullImageViewer(urls: [url], startIndex: 0) { viewerOpen = false }
                    .presentationBackground(.clear)
                    .employeeAppearanceChrome()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                let size = cssClamp(12, 0.018, 16, width: width)
                Text(category.uppercased())
                    .font(appearance.body(size, weight: .bold))
                    .kerning(size * 0.2)
                    .foregroundStyle(appearance.secondaryInk(Color(hex: 0x6E6E6E)))
                if let style = design.styleAesthetic?.trimmed.nilIfEmpty {
                    let chip = cssClamp(10, 0.015, 12, width: width)
                    Text(style)
                        .font(appearance.body(chip, weight: .medium))
                        .kerning(chip * 0.02)
                        .foregroundStyle(appearance.ink(Color(hex: 0x515151)))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6).stroke(appearance.line(Color(hex: 0xA8A8A8)), lineWidth: 1)
                        }
                }
            }
            let titleSize = cssClamp(24, 0.04, 38, width: width)
            Text(title)
                .font(appearance.display(titleSize))
                .kerning(titleSize * 0.025)
                .lineSpacing(titleSize * 0.2)
                .foregroundStyle(appearance.ink(.black))
                .multilineTextAlignment(.center)
        }
    }

    private var imageBox: some View {
        let buttonSize: CGFloat = 48

        return Button { if design.imageLink != nil { viewerOpen = true } } label: {
            appearance.quiet(Color(hex: 0xF5F5F5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if let url = design.imageLink {
                        ProtectedImageView(url: url, contentMode: .scaleAspectFit, watermark: true, multiply: !appearance.dark)
                    } else {
                        Text("No image")
                            .font(appearance.body(14, weight: .light))
                            .foregroundStyle(appearance.muted)
                    }
                }
                .clipShape(.rect(cornerRadius: appearance.enabled ? appearance.cardRadius : 4))
                .overlay { RoundedRectangle(cornerRadius: appearance.enabled ? appearance.cardRadius : 4).stroke(Color(hex: 0xF3F4F6).opacity(0.6), lineWidth: 1) }
                .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("View image of \(title)")
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
        let twoColumns = columnWidth >= 540 && !dynamicTypeSize.isAccessibilitySize
        let columnSize = (columnWidth - 24) / 2

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
    @Environment(\.employeeAppearance) private var appearance
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
                        .font(appearance.body(14))
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
                    Text("Back").font(appearance.body(14, weight: .medium))
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
                    .font(appearance.body(13))
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
