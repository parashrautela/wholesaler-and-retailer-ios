import SwiftUI
import Combine

struct ChamakGeneratingView: View {
    @Bindable var vm: ChamakViewModel
    @State private var pulseScale: CGFloat = 1.0
    @State private var rippleScale: CGFloat = 0.95
    @State private var rippleOpacity: Double = 0.4
    @State private var currentShapeIndex = 0
    @State private var currentFactIndex = 0

    private let shapeTimer = Timer.publish(every: 2.8, on: .main, in: .common).autoconnect()
    private let factTimer = Timer.publish(every: 4.2, on: .main, in: .common).autoconnect()

    private let designFacts: [String] = [
        "“Design is not just what it looks like and feels like. Design is how it works.”",
        "Kundankari is one of India's oldest jewellery arts, setting uncut gems into pure 24K gold foil.",
        "Filigree — twisting fine gold and silver threads — traces back over 5,000 years in Indian tradition.",
        "Every hand-finished bezel is crafted to capture and reflect light from every angle.",
        "In royal Indian jewellery, Meenakari enamelling was created to protect the gold beneath from wear.",
        "True luxury is the seamless dialogue between heritage craftsmanship and contemporary form.",
        "Balance between weight, proportion, and movement turns ornaments into wearable sculpture."
    ]

    private var titlePrefix: String {
        if vm.step == .analyzing {
            return vm.mode == .setCreation ? "Preparing" : "Analyzing"
        }
        return vm.mode == .setCreation ? "Staging" : "Crafting"
    }

    private var titleSuffix: String {
        if vm.step == .analyzing {
            return vm.mode == .setCreation ? "your pieces" : "your designs"
        }
        return vm.mode == .setCreation ? "your set" : "your design"
    }

    private var subtitleText: String {
        if vm.step == .analyzing {
            return vm.mode == .setCreation
                ? "Checking photos and preparing your staging studio."
                : "Breaking down your designs to craft a fresh perspective."
        }
        return vm.mode == .setCreation
            ? "Arranging your pieces with master jewellery composition."
            : "Synthesizing elements into a bespoke jewellery masterpiece."
    }

    var body: some View {
        ZStack {
            // Ethereal pastel gradient background (matching Figma iPhone 16 - 9)
            LinearGradient(
                stops: [
                    .init(color: Color.white, location: 0.0),
                    .init(color: Color(hex: 0xFAF5F7), location: 0.25),
                    .init(color: Color(hex: 0xF3E8FF), location: 0.55),
                    .init(color: Color(hex: 0xFCE7F3), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Subtle diffused color glows
            GeometryReader { geo in
                ZStack {
                    // Lavender aura on lower left
                    Circle()
                        .fill(Color(hex: 0xC084FC).opacity(0.35))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 65)
                        .position(x: geo.size.width * 0.15, y: geo.size.height * 0.65)

                    // Blush pink aura on lower right
                    Circle()
                        .fill(Color(hex: 0xF472B6).opacity(0.4))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 65)
                        .position(x: geo.size.width * 0.85, y: geo.size.height * 0.65)

                    // Center soft radiant glow
                    Circle()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: 250, height: 250)
                        .blur(radius: 45)
                        .position(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Typography
                VStack(spacing: 6) {
                    Text(titlePrefix)
                        .font(.cirka(38, weight: .bold))
                        .foregroundStyle(Palette.dark)

                    Text(titleSuffix)
                        .font(.cirka(38, weight: .regular))
                        .italic()
                        .foregroundStyle(Color(hex: 0xDE6B7C))

                    Text(subtitleText)
                        .font(.manrope(14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x6B7280))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, 4)
                }
                .padding(.top, 60)

                Spacer()

                // Center Soft Dynamic Morphing Jewel Animation
                bloomingAuraCenter

                Spacer()

                // Bottom Progress Pill & Rotating Design Facts
                VStack(spacing: Spacing.sm) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .shadow(color: .white, radius: 4)

                        Text("Just few seconds")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.32), in: Capsule())
                    .overlay {
                        Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)

                    // Rotating Design Facts / Insights
                    Text(designFacts[currentFactIndex])
                        .font(.manrope(13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x4B5563))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)
                        .frame(height: 48)
                        .id(currentFactIndex)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .padding(.top, 4)
                }
                .padding(.bottom, 60)
            }
            .padding(.horizontal, Spacing.base)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.08
                rippleScale = 1.15
                rippleOpacity = 0.2
            }
        }
        .onReceive(shapeTimer) { _ in
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                currentShapeIndex = (currentShapeIndex + 1) % 4
            }
        }
        .onReceive(factTimer) { _ in
            withAnimation(.easeInOut(duration: 0.6)) {
                currentFactIndex = (currentFactIndex + 1) % designFacts.count
            }
        }
    }

    // MARK: - Center Soft Dynamic Jewel Emblem

    private var bloomingAuraCenter: some View {
        ZStack {
            // Outermost soft radiant halo
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 250, height: 250)
                .scaleEffect(rippleScale)
                .blur(radius: 28)

            // Middle soft ripple halo
            Circle()
                .stroke(Color.white.opacity(rippleOpacity), lineWidth: 1.5)
                .frame(width: 190, height: 190)
                .scaleEffect(rippleScale)
                .blur(radius: 2)

            // Inner soft radiant glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.65), Color.white.opacity(0.15)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 75
                    )
                )
                .frame(width: 150, height: 150)
                .blur(radius: 16)
                .scaleEffect(pulseScale)

            // Dynamic soft morphing jewelry shape (soft cabochons, no hard edges)
            Group {
                switch currentShapeIndex {
                case 0:
                    SoftBlossomShape()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.95), Color.white.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                case 1:
                    SoftCabochonTrillionShape()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.95), Color.white.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 74, height: 74)
                case 2:
                    SoftCushionGemShape()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.95), Color.white.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 68, height: 68)
                default:
                    SoftTeardropGemShape()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.95), Color.white.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 68, height: 80)
                }
            }
            .blur(radius: 0.3)
            .shadow(color: Color.white.opacity(0.9), radius: 14)
            .shadow(color: Color(hex: 0xF472B6).opacity(0.28), radius: 16)
            .scaleEffect(pulseScale)
            .id(currentShapeIndex)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}

// MARK: - Very Soft Organic Jewellery Shapes (No Hard Edges)

/// 1. Soft Organic Floral Blossom with velvety rounded lobes
private struct SoftBlossomShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.44
        let innerRadius = radius * 0.72
        let petals = 5

        for i in 0..<petals {
            let angle1 = (Double(i) * (360.0 / Double(petals)) - 90.0) * Double.pi / 180.0
            let angleMid = (Double(i) * (360.0 / Double(petals)) + (180.0 / Double(petals)) - 90.0) * Double.pi / 180.0
            let angle2 = (Double(i + 1) * (360.0 / Double(petals)) - 90.0) * Double.pi / 180.0

            let p1 = CGPoint(x: center.x + CGFloat(cos(angle1)) * innerRadius, y: center.y + CGFloat(sin(angle1)) * innerRadius)
            let tip = CGPoint(x: center.x + CGFloat(cos(angleMid)) * radius, y: center.y + CGFloat(sin(angleMid)) * radius)
            let p2 = CGPoint(x: center.x + CGFloat(cos(angle2)) * innerRadius, y: center.y + CGFloat(sin(angle2)) * innerRadius)

            if i == 0 { path.move(to: p1) }
            path.addQuadCurve(
                to: tip,
                control: CGPoint(x: (p1.x + tip.x) / 2 + CGFloat(cos(angleMid)) * 5, y: (p1.y + tip.y) / 2 + CGFloat(sin(angleMid)) * 5)
            )
            path.addQuadCurve(
                to: p2,
                control: CGPoint(x: (tip.x + p2.x) / 2 + CGFloat(cos(angleMid)) * 5, y: (tip.y + p2.y) / 2 + CGFloat(sin(angleMid)) * 5)
            )
        }
        path.closeSubpath()
        return path
    }
}

/// 2. Soft Cabochon Trillion: Outward-curving pillow triangle with large rounded vertices
private struct SoftCabochonTrillionShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 8
        let r = rect.insetBy(dx: inset, dy: inset)

        let pTop = CGPoint(x: r.midX, y: r.minY + 6)
        let pBottomRight = CGPoint(x: r.maxX - 6, y: r.maxY - 6)
        let pBottomLeft = CGPoint(x: r.minX + 6, y: r.maxY - 6)

        // Pillowy outward-bowing control points
        let ctrlRight = CGPoint(x: r.maxX + 10, y: r.midY - 2)
        let ctrlBottom = CGPoint(x: r.midX, y: r.maxY + 14)
        let ctrlLeft = CGPoint(x: r.minX - 10, y: r.midY - 2)

        path.move(to: CGPoint(x: r.midX - 12, y: r.minY + 12))
        path.addQuadCurve(to: CGPoint(x: r.midX + 12, y: r.minY + 12), control: pTop)
        path.addQuadCurve(to: CGPoint(x: r.maxX - 8, y: r.maxY - 18), control: ctrlRight)
        path.addQuadCurve(to: CGPoint(x: r.maxX - 20, y: r.maxY - 6), control: pBottomRight)
        path.addQuadCurve(to: CGPoint(x: r.minX + 20, y: r.maxY - 6), control: ctrlBottom)
        path.addQuadCurve(to: CGPoint(x: r.minX + 8, y: r.maxY - 18), control: pBottomLeft)
        path.addQuadCurve(to: CGPoint(x: r.midX - 12, y: r.minY + 12), control: ctrlLeft)
        path.closeSubpath()
        return path
    }
}

/// 3. Soft Cushion Cabochon: Continuous squircle with generous radius
private struct SoftCushionGemShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cornerRadius = min(rect.width, rect.height) * 0.36
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect.insetBy(dx: 4, dy: 4))
    }
}

/// 4. Soft Teardrop Pear: Gentle rounded pear/drop with smooth curvature
private struct SoftTeardropGemShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.insetBy(dx: 6, dy: 6)

        let top = CGPoint(x: r.midX, y: r.minY + 8)
        let bottom = CGPoint(x: r.midX, y: r.maxY)

        path.move(to: CGPoint(x: r.midX - 8, y: r.minY + 16))
        path.addQuadCurve(to: CGPoint(x: r.midX + 8, y: r.minY + 16), control: top)
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: r.maxX + 10, y: r.midY + r.height * 0.15),
            control2: CGPoint(x: r.maxX - 6, y: r.maxY)
        )
        path.addCurve(
            to: CGPoint(x: r.midX - 8, y: r.minY + 16),
            control1: CGPoint(x: r.minX + 6, y: r.maxY),
            control2: CGPoint(x: r.minX - 10, y: r.midY + r.height * 0.15)
        )
        path.closeSubpath()
        return path
    }
}
