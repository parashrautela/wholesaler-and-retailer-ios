import SwiftUI

struct ChamakGeneratingView: View {
    @Bindable var vm: ChamakViewModel

    private var activeQuote: ChamakQuote {
        let list = ChamakQuote.quotes
        guard !list.isEmpty else {
            return ChamakQuote(text: "Crafting jewelry perfection...", author: "JewelIndia")
        }
        return list[vm.activeQuoteIndex % list.count]
    }

    var body: some View {
        ZStack {
            // Ambient luxury background
            LinearGradient(
                colors: [Color(hex: 0x1A140F), Color(hex: 0x0A0A0A)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: Spacing.xxl) {
                topStatusBar

                Spacer()

                animatedAuraCenter

                quoteCard
                    .padding(.horizontal, Spacing.xl)

                Spacer()

                bottomFooter
            }
            .padding(.vertical, Spacing.xl)
        }
    }

    // MARK: - Top Status Bar

    private var topStatusBar: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(Color(hex: 0xF6E0A7))
            Text(vm.step == .analyzing ? "AI Vision Analysis in Progress" : "Generating Fused Design 3")
                .font(.manrope(14, weight: .semibold))
                .foregroundStyle(Color(hex: 0xF6E0A7))
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
    }

    // MARK: - Animated Center Graphic

    private var animatedAuraCenter: some View {
        ZStack {
            // Outer glowing ring
            Circle()
                .stroke(Color(hex: 0xD4AF37).opacity(0.2), lineWidth: 2)
                .frame(width: 170, height: 170)

            // Inner pulsing ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xBB8651).opacity(0.35), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 90
                    )
                )
                .frame(width: 150, height: 150)

            // Center emblem
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars.inverse")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: 0xF6E0A7), Color(hex: 0xBB8651)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                ProgressView()
                    .tint(Color(hex: 0xF6E0A7))
                    .scaleEffect(0.9)
            }
        }
    }

    // MARK: - Rotating Quote Card

    private var quoteCard: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "quote.opening")
                .font(.system(size: 24))
                .foregroundStyle(Color(hex: 0xBB8651).opacity(0.8))

            Text(activeQuote.text)
                .font(.cirka(18, weight: .medium))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .animation(.easeInOut(duration: 0.6), value: vm.activeQuoteIndex)

            Text("— \(activeQuote.author)")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color(hex: 0xF6E0A7).opacity(0.8))
                .tracking(1)
                .textCase(.uppercase)
                .animation(.easeInOut(duration: 0.6), value: vm.activeQuoteIndex)
        }
        .padding(Spacing.xl)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: 0xBB8651).opacity(0.2), lineWidth: 1)
        }
    }

    // MARK: - Footer

    private var bottomFooter: some View {
        VStack(spacing: Spacing.sm) {
            Text("Chamak 4-Stage AI Pipeline")
                .font(.manrope(11, weight: .bold))
                .foregroundStyle(Color(hex: 0x9CA3AF))
                .tracking(1.2)
                .textCase(.uppercase)

            Text("Please keep the app open while our model synthesizes your piece.")
                .font(.manrope(12))
                .foregroundStyle(Color(hex: 0x6B7280))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.xl)
    }
}
