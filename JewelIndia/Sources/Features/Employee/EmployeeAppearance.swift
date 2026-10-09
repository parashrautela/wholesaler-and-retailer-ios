import SwiftUI

/// Personal employee styles are independent of the retailer's purchased store theme.
enum EmployeeStyle: String, CaseIterable, Identifiable {
    case original, sarvam, jaipur, aegean, neelam
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Original"
        case .sarvam: "Sarvam"
        case .jaipur: "Jaipur"
        case .aegean: "Aegean"
        case .neelam: "Neelam Atelier"
        }
    }
    var subtitle: String {
        switch self {
        case .original: "Your store theme"
        case .sarvam: "Soft contemporary"
        case .jaipur: "An Indian courtyard"
        case .aegean: "A Greek gallery"
        case .neelam: "The modern Indian atelier"
        }
    }
    var symbol: String {
        switch self {
        case .original: "building.2"
        case .sarvam: "circle.lefthalf.filled"
        case .jaipur: "sun.max"
        case .aegean: "building.columns"
        case .neelam: "diamond"
        }
    }
}

/// A value passed only into the employee hierarchy; shared screens keep their default style.
struct EmployeeAppearance {
    var style: EmployeeStyle = .original
    var inEmployeeView = false
    var enabled: Bool { style != .original }
    var creative: Bool { [.jaipur, .aegean, .neelam].contains(style) }
    var dark: Bool { style == .neelam }

    static let preferenceKey = "jewel_employee_style"
    static let legacyPreferenceKey = "jewel_employee_sarvam"
    static var initialStyle: EmployeeStyle {
        if let saved = UserDefaults.standard.string(forKey: preferenceKey), let style = EmployeeStyle(rawValue: saved) { return style }
        return UserDefaults.standard.bool(forKey: legacyPreferenceKey) ? .sarvam : .original
    }
    static let matterRegular = "EmployeeMatter-Regular"
    static let matterMedium = "EmployeeMatter-Medium"
    static let matterBold = "EmployeeMatter-Bold"
    static let season = "EmployeeSeasonMix-Regular"

    func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch style {
        case .original, .jaipur: return .manrope(size, weight: weight)
        case .aegean, .neelam: return .satoshi(size, weight: weight)
        case .sarvam:
            let face: String
            switch weight {
            case .heavy, .black: face = Self.matterBold
            case .medium, .semibold, .bold: face = Self.matterMedium
            default: face = Self.matterRegular
            }
            return .custom(face, size: size, relativeTo: .body)
        }
    }
    func display(_ size: CGFloat) -> Font {
        switch style {
        case .original, .jaipur, .aegean: .gilda(size)
        case .sarvam: .custom(Self.season, size: size, relativeTo: .largeTitle)
        case .neelam: .cirka(size, weight: .light)
        }
    }
    func cirka(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard enabled else { return .cirka(size, weight: weight) }
        return size >= 24 ? display(size) : body(size, weight: .medium)
    }
    func satoshi(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        enabled ? body(size, weight: weight) : .satoshi(size, weight: weight)
    }
    func gilroy(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        enabled ? body(size, weight: weight) : .gilroy(size, weight: weight)
    }

    var background: Color {
        switch style {
        case .original: Palette.background
        case .sarvam: Color(hex: 0xFCFCFC)
        case .jaipur: Color(hex: 0xFBF4E9)
        case .aegean: Color(hex: 0xF5F7F9)
        case .neelam: Color(hex: 0x101C29)
        }
    }
    var surface: Color {
        switch style {
        case .jaipur: Color(hex: 0xFFFAF2)
        case .neelam: Color(hex: 0x1A2B3B)
        default: .white
        }
    }
    var subtle: Color {
        switch style {
        case .original, .sarvam: Color(hex: 0xF5F5F5)
        case .jaipur: Color(hex: 0xF0E4D3)
        case .aegean: Color(hex: 0xE9EEF5)
        case .neelam: Color(hex: 0x22384A)
        }
    }
    var text: Color {
        switch style {
        case .original: Palette.foreground
        case .sarvam: Color(hex: 0x1F1F1F)
        case .jaipur: Color(hex: 0x442C26)
        case .aegean: Color(hex: 0x142D4A)
        case .neelam: Color(hex: 0xF7F0E3)
        }
    }
    var muted: Color {
        switch style {
        case .original: Palette.muted
        case .sarvam: Color(hex: 0x666666)
        case .jaipur: Color(hex: 0x806B5B)
        case .aegean: Color(hex: 0x637285)
        case .neelam: Color(hex: 0xADBDC9)
        }
    }
    var border: Color {
        switch style {
        case .original, .sarvam: Color(hex: 0xE6E6E6)
        case .jaipur: Color(hex: 0xDCC7AC)
        case .aegean: Color(hex: 0xCFD9E7)
        case .neelam: Color(hex: 0x385066)
        }
    }
    var accent: Color {
        switch style {
        case .original: Color(hex: 0x111827)
        case .sarvam: Color(hex: 0x3333CC)
        case .jaipur: Color(hex: 0x8D333F)
        case .aegean: Color(hex: 0x2455A4)
        case .neelam: Color(hex: 0xD6B77A)
        }
    }
    var selected: Color {
        switch style {
        case .original, .sarvam: Color(hex: 0xE8EFFC)
        case .jaipur: Color(hex: 0xF2DDD7)
        case .aegean: Color(hex: 0xDFE9F7)
        case .neelam: Color(hex: 0x304250)
        }
    }
    var onAccent: Color { dark ? Color(hex: 0x172431) : .white }
    var primaryStart: Color {
        switch style {
        case .original: Color(hex: 0x3C3C3C)
        case .sarvam: Color(hex: 0x3A3F5C)
        case .jaipur: Color(hex: 0x9D4850)
        case .aegean: Color(hex: 0x3366B4)
        case .neelam: Color(hex: 0xE9C993)
        }
    }
    var primaryEnd: Color {
        switch style {
        case .original: .black
        case .sarvam: Color(hex: 0x1E2033)
        case .jaipur: Color(hex: 0x742D38)
        case .aegean: Color(hex: 0x204682)
        case .neelam: Color(hex: 0xC5A66D)
        }
    }
    var primary: LinearGradient { LinearGradient(colors: [primaryStart, primaryEnd], startPoint: .top, endPoint: .bottom) }
    var cardRadius: CGFloat {
        switch style { case .original: 18; case .sarvam: 12; case .jaipur: 6; case .aegean: 3; case .neelam: 2 }
    }
    var controlRadius: CGFloat { creative ? (style == .jaipur ? 8 : 4) : 999 }
    var imageRatio: CGFloat { style == .jaipur ? 0.88 : style == .neelam ? 0.82 : 1 }
    var headingTracking: CGFloat { style == .aegean ? 0.5 : style == .neelam ? -0.6 : -0.5 }
    func ink(_ original: Color) -> Color { enabled ? text : original }
    func secondaryInk(_ original: Color) -> Color { enabled ? muted : original }
    func panel(_ original: Color = .white) -> Color { enabled ? surface : original }
    func quiet(_ original: Color) -> Color { enabled ? subtle : original }
    func line(_ original: Color) -> Color { enabled ? border : original }
}

private struct EmployeeAppearanceKey: EnvironmentKey {
    static let defaultValue = EmployeeAppearance()
}

extension EnvironmentValues {
    var employeeAppearance: EmployeeAppearance {
        get { self[EmployeeAppearanceKey.self] }
        set { self[EmployeeAppearanceKey.self] = newValue }
    }
}

/// Presentations observe the same preference without resetting their data or selection.
private struct EmployeeAppearanceChrome: ViewModifier {
    @AppStorage(EmployeeAppearance.preferenceKey) private var selectedStyle = EmployeeAppearance.initialStyle.rawValue
    var isRetailer: Bool
    var onWishlists: (() -> Void)?
    var onCredits: (() -> Void)?
    var onProfile: (() -> Void)?
    private var appearance: EmployeeAppearance { EmployeeAppearance(style: EmployeeStyle(rawValue: selectedStyle) ?? .original, inEmployeeView: true) }

    func body(content: Content) -> some View {
        // Reserve real layout space above each navigation container. A safe-area
        // inset on NavigationStack lets its native toolbar overlap the mode bar.
        VStack(spacing: 0) {
            EmployeeModeBar(selectedStyle: $selectedStyle, isRetailer: isRetailer,
                            onWishlists: onWishlists, onCredits: onCredits, onProfile: onProfile)
                .zIndex(1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.employeeAppearance, appearance)
        .tint(appearance.enabled ? appearance.accent : .accentColor)
        .preferredColorScheme(appearance.dark ? .dark : .light)
    }
}

extension View {
    func employeeAppearanceChrome(isRetailer: Bool = false,
                                  onWishlists: (() -> Void)? = nil,
                                  onCredits: (() -> Void)? = nil,
                                  onProfile: (() -> Void)? = nil) -> some View {
        modifier(EmployeeAppearanceChrome(isRetailer: isRetailer,
                                          onWishlists: onWishlists, onCredits: onCredits, onProfile: onProfile))
    }

    func employeeCard() -> some View { modifier(EmployeeCardAppearance()) }

    /// Shared sheets gain employee chrome only when opened from an employee screen.
    func employeePresentationChrome() -> some View { modifier(EmployeePresentationChrome()) }
}

private struct EmployeePresentationChrome: ViewModifier {
    @Environment(\.employeeAppearance) private var appearance
    @ViewBuilder func body(content: Content) -> some View {
        if appearance.inEmployeeView { content.employeeAppearanceChrome() }
        else { content }
    }
}

private struct EmployeeModeBar: View {
    @Binding var selectedStyle: String
    var isRetailer: Bool
    var onWishlists: (() -> Void)?
    var onCredits: (() -> Void)?
    var onProfile: (() -> Void)?
    private var appearance: EmployeeAppearance { EmployeeAppearance(style: EmployeeStyle(rawValue: selectedStyle) ?? .original, inEmployeeView: true) }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isRetailer ? "Employee View Active" : "Employee view")
                    .font(appearance.body(13, weight: .medium))
                    .foregroundStyle(appearance.muted)
                if appearance.creative {
                    Text(appearance.style.subtitle.uppercased())
                        .font(appearance.body(9, weight: .medium)).kerning(1.2)
                        .foregroundStyle(appearance.accent)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Menu {
                Picker("Employee style", selection: $selectedStyle) {
                    Section("New directions") {
                        ForEach([EmployeeStyle.jaipur, .aegean, .neelam]) { style in
                            Label(style.title, systemImage: style.symbol).tag(style.rawValue)
                        }
                    }
                    Section("Previous styles") {
                        ForEach([EmployeeStyle.original, .sarvam]) { style in
                            Label(style.title, systemImage: style.symbol).tag(style.rawValue)
                        }
                    }
                }
            } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Image(systemName: appearance.style.symbol).font(.system(size: 15))
                        Text(appearance.style.title).font(appearance.body(14, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    HStack(spacing: 8) {
                        Image(systemName: appearance.style.symbol).font(.system(size: 18))
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundStyle(appearance.text)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(appearance.subtle, in: .rect(cornerRadius: appearance.controlRadius))
                .overlay { RoundedRectangle(cornerRadius: appearance.controlRadius).stroke(appearance.border, lineWidth: 1) }
            }
            .accessibilityLabel("Employee style")
            .accessibilityValue(appearance.style.title)
            .accessibilityHint("Choose Jaipur, Aegean, Neelam Atelier, Original or Sarvam")
            .accessibilityIdentifier("employee-style-picker")
            if onProfile != nil {
                Menu {
                    if let onWishlists { Button("Customer wishlists", systemImage: "heart", action: onWishlists) }
                    if let onCredits { Button("Daily credits", systemImage: "sun.max", action: onCredits) }
                    if let onProfile { Button("Profile", systemImage: "person", action: onProfile) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(appearance.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Employee menu")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .frame(maxWidth: .infinity)
        .background(appearance.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(appearance.border).frame(height: 1) }
    }
}

/// Working panels take their geometry and colour from the selected employee style.
private struct EmployeeCardAppearance: ViewModifier {
    @Environment(\.employeeAppearance) private var appearance
    @ViewBuilder func body(content: Content) -> some View {
        if appearance.enabled {
            content
                .padding(.bottom, 16)
                .background(appearance.surface)
                .clipShape(.rect(cornerRadius: appearance.cardRadius))
                .overlay { RoundedRectangle(cornerRadius: appearance.cardRadius).stroke(appearance.border, lineWidth: 1) }
        } else { content }
    }
}

struct EmployeeHeroGradient: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(hex: 0xFCFCFC)
                Ellipse().fill(Color(hex: 0xA5BBFC).opacity(0.55))
                    .frame(width: geo.size.width * 1.1, height: 340).offset(y: -30).blur(radius: 70)
                Ellipse().fill(Color(hex: 0xEE7944).opacity(0.65))
                    .frame(width: geo.size.width * 0.65, height: 220).offset(y: -90).blur(radius: 70)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

struct EmployeeSarvamButtonStyle: ButtonStyle {
    @Environment(\.employeeAppearance) private var appearance
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        let type = appearance
        configuration.label
            .font(type.body(16, weight: .medium))
            .foregroundStyle(secondary ? type.text : type.onAccent)
            .padding(.horizontal, 24)
            .frame(minHeight: 48)
            .background(secondary ? LinearGradient(colors: [type.surface, type.subtle], startPoint: .top, endPoint: .bottom) : type.primary, in: .rect(cornerRadius: type.controlRadius))
            .overlay { RoundedRectangle(cornerRadius: type.controlRadius).stroke(secondary ? type.border : Color.clear, lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Original vector ornament, drawn at the current size. Kept out of working content.
struct EmployeeStyleMotif: View {
    @Environment(\.employeeAppearance) private var appearance
    var body: some View {
        Canvas { context, size in
            var path = Path()
            switch appearance.style {
            case .jaipur:
                let step: CGFloat = 40
                for x in stride(from: CGFloat(0), through: size.width, by: step) {
                    let y = size.height / 2
                    path.move(to: CGPoint(x: x, y: y - 10))
                    path.addLine(to: CGPoint(x: x + 10, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + 10))
                    path.addLine(to: CGPoint(x: x - 10, y: y))
                    path.closeSubpath()
                    path.move(to: CGPoint(x: x + 14, y: y))
                    path.addLine(to: CGPoint(x: x + 26, y: y))
                }
            case .aegean:
                let h = min(size.height - 4, 18), y = (size.height - h) / 2
                for x in stride(from: CGFloat(0), through: size.width, by: 40) {
                    path.move(to: CGPoint(x: x, y: y + h))
                    for point in [CGPoint(x: x, y: y), CGPoint(x: x + 30, y: y), CGPoint(x: x + 30, y: y + h), CGPoint(x: x + 10, y: y + h), CGPoint(x: x + 10, y: y + 6), CGPoint(x: x + 22, y: y + 6), CGPoint(x: x + 22, y: y + 12)] {
                        path.addLine(to: point)
                    }
                }
            case .neelam:
                let y = size.height / 2
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width * 0.42, y: y))
                let center = size.width / 2
                path.move(to: CGPoint(x: center, y: y - 10))
                path.addLine(to: CGPoint(x: center + 16, y: y))
                path.addLine(to: CGPoint(x: center, y: y + 10))
                path.addLine(to: CGPoint(x: center - 16, y: y)); path.closeSubpath()
                path.move(to: CGPoint(x: size.width * 0.58, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            default: break
            }
            context.stroke(path, with: .color(appearance.accent.opacity(0.4)), lineWidth: 1)
        }
        .frame(height: 24)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct EmployeeCourtyardArch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.width / 2, center = CGPoint(x: rect.midX, y: rect.minY + r * 1.05)
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: center.y))
        for i in 0..<8 {
            let a = CGFloat.pi + CGFloat(i) * .pi / 8
            let b = a + .pi / 8, m = (a + b) / 2
            p.addQuadCurve(to: CGPoint(x: center.x + r * cos(b), y: center.y + r * sin(b)),
                           control: CGPoint(x: center.x + r * 1.12 * cos(m), y: center.y + r * 1.12 * sin(m)))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

struct EmployeeCreativeBackdrop: View {
    @Environment(\.employeeAppearance) private var appearance
    var body: some View {
        GeometryReader { geo in
            ZStack {
                appearance.background
                if appearance.style == .jaipur {
                    LinearGradient(colors: [Color(hex: 0xECD4BB).opacity(0.65), appearance.background], startPoint: .top, endPoint: .bottom)
                    HStack {
                        EmployeeJaliPattern().frame(width: min(geo.size.width * 0.12, 120))
                        Spacer()
                        EmployeeJaliPattern().frame(width: min(geo.size.width * 0.12, 120))
                    }
                    .mask(LinearGradient(colors: [.clear, .white, .clear], startPoint: .top, endPoint: .bottom))
                    EmployeeCourtyardArch().stroke(appearance.border, lineWidth: 1)
                        .frame(width: min(geo.size.width * 0.78, 600), height: geo.size.height * 0.82)
                        .offset(y: geo.size.height * 0.03)
                    EmployeeCourtyardArch().stroke(appearance.border.opacity(0.6), lineWidth: 1)
                        .frame(width: min(geo.size.width * 0.83, 636), height: geo.size.height * 0.87)
                        .offset(y: geo.size.height * 0.03)
                } else if appearance.style == .aegean {
                    LinearGradient(colors: [Color(hex: 0xE3EAF3), appearance.background, .white], startPoint: .topLeading, endPoint: .bottomTrailing)
                    HStack {
                        column
                        Spacer()
                        column
                    }.padding(.horizontal, 24).opacity(0.45)
                } else if appearance.style == .neelam {
                    LinearGradient(colors: [Color(hex: 0x284657), appearance.background], startPoint: .topTrailing, endPoint: .bottomLeading)
                    EmployeeStyleEmblem().frame(width: 320, height: 320)
                        .opacity(0.16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).offset(x: 110, y: -60)
                    Canvas { context, size in
                        var p = Path()
                        for i in 0..<6 {
                            let x = size.width * 0.68 + CGFloat(i) * 32
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: size.width, y: size.height * 0.55 + CGFloat(i) * 38))
                        }
                        context.stroke(p, with: .color(appearance.accent.opacity(0.13)), lineWidth: 1)
                    }
                }
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
    private var column: some View {
        VStack(spacing: 0) {
            Rectangle().frame(height: 6)
            Rectangle().frame(height: 3).padding(.horizontal, 5).padding(.top, 4)
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { _ in Rectangle().frame(width: 1) }
            }.padding(.vertical, 12)
            Rectangle().frame(height: 3).padding(.horizontal, 5)
            Rectangle().frame(height: 6).padding(.top, 4)
        }
        .frame(width: 44).padding(.vertical, 56).foregroundStyle(appearance.accent)
    }
}

/// Small architectural and gem emblems, authored as vectors rather than generic icons.
struct EmployeeStyleEmblem: View {
    @Environment(\.employeeAppearance) private var appearance
    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) * 0.42
            var p = Path()
            switch appearance.style {
            case .jaipur:
                p.addEllipse(in: CGRect(x: c.x-r*0.52, y: c.y-r*0.52, width: r*1.04, height: r*1.04))
                for i in 0..<12 {
                    let a = CGFloat(i) * .pi / 6
                    let tip = CGPoint(x: c.x + cos(a)*r, y: c.y + sin(a)*r)
                    let l = CGPoint(x: c.x + cos(a-0.19)*r*0.49, y: c.y + sin(a-0.19)*r*0.49)
                    let q = CGPoint(x: c.x + cos(a+0.19)*r*0.49, y: c.y + sin(a+0.19)*r*0.49)
                    p.move(to: l)
                    p.addQuadCurve(to: tip, control: CGPoint(x: c.x+cos(a-0.18)*r*0.88, y: c.y+sin(a-0.18)*r*0.88))
                    p.addQuadCurve(to: q, control: CGPoint(x: c.x+cos(a+0.18)*r*0.88, y: c.y+sin(a+0.18)*r*0.88))
                }
            case .aegean:
                for side: CGFloat in [-1, 1] {
                    var stem = Path()
                    stem.move(to: CGPoint(x: c.x, y: c.y+r))
                    stem.addQuadCurve(to: CGPoint(x: c.x+side*r*0.5, y: c.y-r*0.82), control: CGPoint(x: c.x+side*r*1.2, y: c.y))
                    p.addPath(stem)
                    for i in 0..<6 {
                        let t = CGFloat(i)/5
                        let y = c.y+r*0.65-t*r*1.3
                        let x = c.x+side*r*(0.65+0.18*sin(t * .pi))
                        var leaf = Path()
                        leaf.move(to: CGPoint(x: x, y: y))
                        leaf.addQuadCurve(to: CGPoint(x: x+side*r*0.3, y: y-r*0.28), control: CGPoint(x: x+side*r*0.38, y: y-r*0.02))
                        leaf.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x+side*r*0.05, y: y-r*0.3))
                        p.addPath(leaf)
                    }
                }
                p.move(to: CGPoint(x: c.x-r*0.18,y:c.y+r));p.addLine(to:CGPoint(x:c.x+r*0.18,y:c.y+r))
            case .neelam:
                let vertices = [CGPoint(x:c.x-r*0.58,y:c.y-r*0.7),CGPoint(x:c.x+r*0.58,y:c.y-r*0.7),CGPoint(x:c.x+r,y:c.y-r*0.12),CGPoint(x:c.x,y:c.y+r),CGPoint(x:c.x-r,y:c.y-r*0.12)]
                p.addLines(vertices);p.closeSubpath()
                let l=CGPoint(x:c.x-r*0.48,y:c.y-r*0.12),q=CGPoint(x:c.x+r*0.48,y:c.y-r*0.12)
                p.move(to:vertices[4]);p.addLine(to:vertices[2])
                p.move(to:vertices[0]);p.addLine(to:l);p.addLine(to:vertices[3]);p.addLine(to:q);p.addLine(to:vertices[1])
                p.move(to:l);p.addLine(to:CGPoint(x:c.x,y:c.y-r*0.7));p.addLine(to:q)
                context.fill(p, with: .color(appearance.accent.opacity(0.05)))
            default: break
            }
            context.stroke(p, with: .color(appearance.accent.opacity(0.75)), lineWidth: 1)
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct EmployeeJaliPattern: View {
    @Environment(\.employeeAppearance) private var appearance
    var body: some View {
        Canvas { context, size in
            var p = Path()
            let step: CGFloat = 34
            for x in stride(from: CGFloat(0), through: size.width+step, by: step) {
                for y in stride(from: CGFloat(0), through: size.height+step, by: step) {
                    p.move(to: CGPoint(x:x,y:y-step/2))
                    p.addLine(to:CGPoint(x:x+step/2,y:y));p.addLine(to:CGPoint(x:x,y:y+step/2));p.addLine(to:CGPoint(x:x-step/2,y:y));p.closeSubpath()
                    p.addEllipse(in:CGRect(x:x-2,y:y-2,width:4,height:4))
                }
            }
            context.stroke(p,with:.color(appearance.accent.opacity(0.16)),lineWidth:0.8)
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
