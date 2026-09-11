import SwiftUI

/// What to open the Chamak flow with: a fresh run in a mode, or a saved result.
struct ChamakLaunch: Identifiable {
    let id = UUID()
    let mode: ChamakMode
    var generation: ChamakGeneration? = nil
}

/// The Chamak tab: both AI tools up top, everything they've made below.
///
/// Fusion and Set Creation share one flow, one credit wallet and one gallery,
/// so they share a tab. Each tool still opens `ChamakFlowCoordinator` full
/// screen, exactly as the old menu entries did. The tab only adds a home for
/// them and a gallery you can reach without starting a new run first.
struct ChamakHubView: View {
    @Environment(SessionStore.self) private var session
    @Environment(CreditStore.self) private var credits
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var gallery: ChamakViewModel
    @State private var launch: ChamakLaunch?
    @State private var hasLoaded = false

    /// Two columns on a phone, four or five on an iPad, rather than two
    /// oversized tiles stretched across the whole width.
    static let galleryColumns = [
        GridItem(.adaptive(minimum: 165, maximum: 260), spacing: Spacing.md)
    ]

    /// `gallery` is injectable only so a debug peek can show sample tiles.
    init(gallery: ChamakViewModel? = nil) {
        _gallery = State(initialValue: gallery ?? ChamakViewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                toolCards
                gallerySection
            }
            .padding(.horizontal, Spacing.base)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(Color.white)
        .navigationTitle("Chamak")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadGallery() }
        .refreshable {
            await loadGallery()
            await credits.refresh()
        }
        // A run finished in the flow should be in the gallery on the way back.
        .fullScreenCover(item: $launch, onDismiss: { Task { await loadGallery() } }) { launch in
            if let user = session.user {
                ChamakFlowCoordinator(
                    wholesalerID: user.id,
                    mode: launch.mode,
                    openingGeneration: launch.generation
                )
                .environment(credits)
            }
        }
    }

    private func loadGallery() async {
        guard let user = session.user else {
            hasLoaded = true
            return
        }
        await gallery.refreshGallery(wholesalerID: user.id)
        hasLoaded = true
    }

    // MARK: - Tools

    @ViewBuilder
    private var toolCards: some View {
        let fusion = ChamakToolCard(
            style: .gold,
            title: "Chamak Fusion",
            blurb: "Blend two of your designs into a brand new one.",
            actionTitle: "Start Fusion",
            cost: credits.cost(for: "chamak.generate")
        ) {
            launch = ChamakLaunch(mode: .fusion)
        }

        let setCreation = ChamakToolCard(
            style: .cream,
            title: "Set Creation",
            blurb: "Pair two pieces and stage them as one matching set.",
            actionTitle: "Create a Set",
            cost: credits.cost(for: "chamak.set_creation")
        ) {
            launch = ChamakLaunch(mode: .setCreation)
        }

        if horizontalSizeClass == .regular {
            // Side by side, both as tall as the taller one.
            HStack(alignment: .top, spacing: Spacing.base) {
                fusion
                setCreation
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: Spacing.base) {
                fusion
                setCreation
            }
        }
    }

    // MARK: - Gallery

    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your Gallery")
                        .font(.cirka(28))
                        .foregroundStyle(Palette.dark)
                    Spacer()
                    if !gallery.galleryGenerations.isEmpty {
                        let count = gallery.galleryGenerations.count
                        Text("\(count) \(count == 1 ? "creation" : "creations")")
                            .font(.manrope(12, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }
                }

                Text("Everything you make stays private here. Nothing is published to your catalogue.")
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !hasLoaded, gallery.galleryGenerations.isEmpty {
                ProgressView()
                    .tint(Palette.dark)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let message = gallery.galleryErrorMessage, gallery.galleryGenerations.isEmpty {
                galleryMessage(
                    symbol: "exclamationmark.triangle",
                    tint: Color(hex: 0xD97706),
                    title: "Couldn't Load Your Gallery",
                    body: message,
                    actionTitle: "Try Again"
                ) {
                    Task { await loadGallery() }
                }
            } else if gallery.galleryGenerations.isEmpty {
                galleryMessage(
                    symbol: "sparkles.rectangle.stack",
                    tint: Color(hex: 0xBB8651),
                    title: "Nothing Here Yet",
                    body: "Your fusions and sets will appear here as soon as you make them."
                )
            } else {
                LazyVGrid(columns: Self.galleryColumns, spacing: Spacing.md) {
                    ForEach(gallery.galleryGenerations) { gen in
                        ChamakGalleryCard(
                            generation: gen,
                            thumbnailURL: gallery.galleryThumbnailURLs[gen.id]
                        ) {
                            launch = ChamakLaunch(mode: gen.mode, generation: gen)
                        }
                    }
                }
            }
        }
    }

    private func galleryMessage(
        symbol: String,
        tint: Color,
        title: String,
        body: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundStyle(tint.opacity(0.8))

            Text(title)
                .font(.cirka(18, weight: .bold))
                .foregroundStyle(Palette.dark)

            Text(body)
                .font(.manrope(13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Palette.dark, in: .rect(cornerRadius: 8))
                    .buttonStyle(PressableButtonStyle())
                    .disabled(gallery.isRefreshingGallery)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0xFAFAFA), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xF0F0F0), lineWidth: 1)
        }
    }
}

// MARK: - Tool Card

/// A launch card for one Chamak tool. Gold is the headline tool (Fusion), in
/// the same gradient as the Home promo; cream is the quieter sibling.
private struct ChamakToolCard: View {
    enum Style { case gold, cream }

    let style: Style
    let title: String
    let blurb: String
    let actionTitle: String
    let cost: Int?
    let action: () -> Void

    private var isGold: Bool { style == .gold }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(title)
                        .font(.cirka(26, weight: .bold))
                        .foregroundStyle(isGold ? .white : Palette.dark)

                    Text(blurb)
                        .font(.manrope(13))
                        .foregroundStyle(isGold ? .white.opacity(0.95) : Palette.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    actionPill
                        .padding(.top, Spacing.xs)
                }

                Spacer(minLength: 0)

                artwork
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 170, maxHeight: .infinity, alignment: .leading)
            .background { background }
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isGold ? Color(hex: 0xE4CC8F).opacity(0.3) : Color(hex: 0xF3E8D6), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isGold ? 0.08 : 0.03), radius: 6, y: 3)
        }
        .buttonStyle(PressableButtonStyle())
    }

    @ViewBuilder
    private var background: some View {
        if isGold {
            LinearGradient(
                colors: [Color(hex: 0xBB8651), Color(hex: 0xF6E0A7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color(hex: 0xFFFBF4)
        }
    }

    private var actionPill: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isGold ? "wand.and.stars" : "sparkles")
                    .font(.system(size: 13))
                Text(actionTitle)
                    .font(.manrope(14, weight: .bold))
            }

            if let cost, cost > 0 {
                Text("\(cost) credits")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Color(hex: 0xBB8651))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: 0xFFFBF4), in: .capsule)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isGold ? Color.black : Palette.dark, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isGold ? Color(hex: 0xE4CC8F) : .clear, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if isGold {
            Image("ChamakNecklace")
                .resizable()
                .scaledToFit()
                .frame(width: 96)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)
        } else {
            // A necklace and a pair of earrings, overlapped — a set, at a glance.
            ZStack {
                artTile("CatEarrings")
                    .rotationEffect(.degrees(8))
                    .offset(x: 16, y: 10)
                artTile("CatNecklace")
                    .rotationEffect(.degrees(-6))
                    .offset(x: -12, y: -8)
            }
            .frame(width: 104, height: 110)
            .accessibilityHidden(true)
        }
    }

    private func artTile(_ asset: String) -> some View {
        // The category photos carry their name printed across the top, so
        // render taller than the tile and keep only the bottom of the photo.
        Image(asset)
            .resizable()
            .scaledToFill()
            .frame(width: 64, height: 116)
            .frame(width: 64, height: 80, alignment: .bottom)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}
