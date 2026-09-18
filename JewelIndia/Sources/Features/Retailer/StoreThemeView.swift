import SwiftUI

/// Retailer Store Theme picker (`/dashboard/retailer/theme`).
///
/// A direct port of the web's `components/retailer/RetailerThemeClient.jsx`:
/// the same four themes and artwork, the same CLAIM / SELECTED / LOCKED
/// badges, the same claim sequence, and the same `retailers.selected_theme`
/// column — so a theme claimed on either side shows on both.
///
/// Where it goes further than the web: a locked theme with a price on the
/// rate card (`theme.<id>`) can be unlocked with credits. The server refuses
/// to select a priced theme the retailer doesn't own, so the lock here is a
/// courtesy, not the rule.
///
/// The artwork is stored as SVG, which iOS cannot draw; Cloudinary converts
/// it on request, and `ThemeOption.imageURL` asks for WebP at the width a
/// card actually uses (~30 KB instead of ~800 KB as PNG).
struct ThemeOption: Identifiable, Sendable {
    let id: String
    let name: String
    let subtext: String
    /// Cloudinary public id, e.g. "v1778837501/selected_er11az.svg".
    let asset: String
    /// Paid: locked until the retailer owns `priceKey`.
    let locked: Bool

    /// The rate-card and entitlement key for this theme.
    var priceKey: String { "theme.\(id)" }

    var imageURL: URL? {
        URL(string: "https://res.cloudinary.com/dcs0vuzwg/image/upload/f_webp,w_700,q_80/\(asset)")
    }

    static let all: [ThemeOption] = [
        .init(id: "indian", name: "Indian",
              subtext: Self.subtext, asset: "v1778837501/selected_er11az.svg", locked: false),
        // Maharaja is unlocked but unclaimed, exactly as on the web.
        .init(id: "maharaja", name: "Maharaja",
              subtext: Self.subtext, asset: "v1778837496/locked1_sc4thy.svg", locked: false),
        .init(id: "utsav", name: "Utsav",
              subtext: Self.subtext, asset: "v1778837497/locked2_k8imhv.svg", locked: true),
        .init(id: "neelam", name: "Neelam",
              subtext: Self.subtext, asset: "v1778837499/locked3_jztkzz.svg", locked: true)
    ]

    private static let subtext =
        "Discover designs selected with precision, blending craftsmanship and ethnic style"
}

enum ThemePalette {
    static let screen = Color(hex: 0xF0F2F5)
    static let heading = Color(hex: 0x111111)
    static let sub = Color(hex: 0x6B7280)
    static let amber = Color(hex: 0xF59E0B)
    static let amberDeep = Color(hex: 0xEAB308)
    static let emerald = Color(hex: 0x10B981)

    /// The web's `linear-gradient(to top, rgba(0,0,0,.65), rgba(0,0,0,.08) 50%, transparent 75%)`.
    static let cardScrim = LinearGradient(
        stops: [
            .init(color: .black.opacity(0.65), location: 0),
            .init(color: .black.opacity(0.08), location: 0.5),
            .init(color: .clear, location: 0.75)
        ],
        startPoint: .bottom, endPoint: .top
    )
}

struct StoreThemeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(CreditStore.self) private var credits

    /// Mirrors the web's localStorage key so the two stay recognisably the same.
    private static let storageKey = "jewel_store_theme"

    @State private var selectedThemeID: String = UserDefaults.standard
        .string(forKey: StoreThemeView.storageKey) ?? "indian"
    @State private var lockedTheme: ThemeOption?
    @State private var unlockingTheme: ThemeOption?
    @State private var claimingTheme: ThemeOption?
    @State private var ownedKeys: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Store Theme")
                            .font(.manrope(22, weight: .bold))
                            .foregroundStyle(ThemePalette.heading)
                        Text("Select the store theme you think justifies your product and vision")
                            .font(.manrope(13))
                            .foregroundStyle(ThemePalette.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LazyVGrid(columns: columns, spacing: Spacing.lg) {
                        ForEach(ThemeOption.all) { theme in
                            ThemeCard(
                                theme: theme,
                                isSelected: selectedThemeID == theme.id,
                                isLocked: isLocked(theme),
                                price: credits.cost(for: theme.priceKey),
                                action: { tapped(theme) }
                            )
                        }
                    }
                    .frame(maxWidth: 780)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ThemePalette.screen)
            .navigationTitle("Store Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(.manrope(14, weight: .semibold))
                        .foregroundStyle(ThemePalette.heading)
                }
            }
        }
        .task { await loadSelection() }
        .fullScreenCover(item: $lockedTheme) { theme in
            LockedThemeSheet(theme: theme) { lockedTheme = nil }
                .presentationBackground(.clear)
        }
        .fullScreenCover(item: $unlockingTheme) { theme in
            UnlockThemeSheet(theme: theme, price: credits.cost(for: theme.priceKey) ?? 0) {
                unlockingTheme = nil
            } onUnlocked: {
                ownedKeys.insert(theme.priceKey)
                Task {
                    await credits.refresh()
                    await apply(theme)
                    unlockingTheme = nil
                }
            }
            .environment(credits)
            .presentationBackground(.clear)
        }
        .fullScreenCover(item: $claimingTheme) { theme in
            ClaimThemeSheet(theme: theme) {
                claimingTheme = nil
            } onClaimed: {
                Task { await apply(theme) }
            }
            .presentationBackground(.clear)
        }
    }

    /// One column on a phone, two from tablet width — the web's
    /// `grid-cols-1 sm:grid-cols-2`.
    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.lg), count: count)
    }

    private func isLocked(_ theme: ThemeOption) -> Bool {
        theme.locked && !ownedKeys.contains(theme.priceKey)
    }

    private func tapped(_ theme: ThemeOption) {
        if isLocked(theme) {
            // No price means it isn't on sale yet — the web's "coming soon".
            if credits.cost(for: theme.priceKey) != nil {
                unlockingTheme = theme
            } else {
                lockedTheme = theme
            }
        } else if theme.id != selectedThemeID {
            claimingTheme = theme
        }
    }

    private func loadSelection() async {
        guard let user = session.user else { return }
        if let keys = try? await CreditsAPI.fetchEntitlementKeys() {
            ownedKeys = keys
        }
        if let stored = await RetailerAPI.fetchSelectedTheme(userID: user.id) {
            selectedThemeID = stored
            UserDefaults.standard.set(stored, forKey: Self.storageKey)
        }
    }

    private func apply(_ theme: ThemeOption) async {
        selectedThemeID = theme.id
        UserDefaults.standard.set(theme.id, forKey: Self.storageKey)
        claimingTheme = nil
        guard let user = session.user else { return }
        await RetailerAPI.setSelectedTheme(theme.id, userID: user.id)
    }
}

// MARK: - Card

private struct ThemeCard: View {
    let theme: ThemeOption
    let isSelected: Bool
    let isLocked: Bool
    /// Credits to unlock, when the theme is on sale.
    let price: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                CachedImage(url: theme.imageURL)
                    .overlay { ThemePalette.cardScrim }

                badge
                    .padding(16)

                VStack(spacing: 4) {
                    Text(theme.name)
                        .font(.cirka(28, weight: .regular))
                        .foregroundStyle(.white)
                    Text(theme.subtext)
                        .font(.manrope(12))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(ThemePalette.heading, lineWidth: isSelected ? 3 : 0)
            }
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0.10),
                    radius: isSelected ? 16 : 10, y: isSelected ? 12 : 4)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(theme.name) theme, \(badgeLabel)")
    }

    private var badgeLabel: String {
        if isLocked {
            return price.map { "locked, unlock for \(TopUpStyle.count($0)) credits" } ?? "locked"
        }
        return isSelected ? "selected" : "available to claim"
    }

    @ViewBuilder
    private var badge: some View {
        if isLocked {
            pill {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                    Text(price.map { "\(TopUpStyle.count($0)) CREDITS" } ?? "LOCKED")
                }
                .foregroundStyle(.white)
            }
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.3), lineWidth: 1) }
        } else if isSelected {
            pill {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    Text("SELECTED")
                }
                .foregroundStyle(ThemePalette.heading)
            }
            .background(.white, in: Capsule())
        } else {
            pill {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .bold))
                    Text("CLAIM")
                }
                .foregroundStyle(.white)
            }
            .background(
                LinearGradient(colors: [ThemePalette.amber, ThemePalette.amberDeep],
                               startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.manrope(10, weight: .bold))
            .kerning(1.2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

// MARK: - Locked

/// "This theme is coming in ✦ Version 2.0" — the web's `LockedModal`.
private struct LockedThemeSheet: View {
    let theme: ThemeOption
    let onClose: () -> Void

    var body: some View {
        ThemeSheetScaffold(theme: theme, imageOpacity: 1) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 64, height: 64)
                        .overlay { Circle().stroke(.white.opacity(0.3), lineWidth: 1) }
                    Image(systemName: "lock")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 20)

                Text(theme.name)
                    .font(.cirka(28))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                Rectangle()
                    .fill(.white.opacity(0.4))
                    .frame(width: 32, height: 1)
                    .padding(.bottom, 16)

                Text("This theme is coming in")
                    .font(.manrope(13))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 8)

                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 10, weight: .bold))
                    Text("VERSION 2.0")
                }
                .font(.manrope(12, weight: .semibold))
                .kerning(1.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.25), lineWidth: 1) }
                .padding(.bottom, 24)

                Text("We're crafting this experience with care. Stay tuned — it will be worth the wait.")
                    .font(.manrope(12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
                    .padding(.bottom, 32)

                Button(action: onClose) {
                    Text("Got it")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x111111))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
        } onBackdropTap: {
            onClose()
        }
    }
}

// MARK: - Unlock

/// A locked theme that is on sale: its price, the retailer's balance, and one
/// button that pays for it. Falls to Top Up when the wallet is short.
private struct UnlockThemeSheet: View {
    let theme: ThemeOption
    let price: Int
    let onClose: () -> Void
    let onUnlocked: () -> Void

    @Environment(CreditStore.self) private var credits

    @State private var isPaying = false
    @State private var message: String?
    @State private var showTopUp = false

    private var balance: Int { credits.wallet?.available ?? 0 }
    private var isShort: Bool { balance < price }

    var body: some View {
        ThemeSheetScaffold(theme: theme, imageOpacity: 0.9) {
            VStack(spacing: 0) {
                Text("✦ ✦ ✦")
                    .font(.manrope(14))
                    .kerning(6)
                    .foregroundStyle(ThemePalette.amber)
                    .padding(.bottom, 20)

                Text("Unlock the \(theme.name) theme")
                    .font(.cirka(24))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .padding(.bottom, 16)

                Rectangle()
                    .fill(ThemePalette.amber.opacity(0.5))
                    .frame(width: 32, height: 1)
                    .padding(.bottom, 20)

                Text("\(TopUpStyle.count(price)) credits · yours to keep")
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 6)

                Text("You have \(TopUpStyle.count(balance)) credits")
                    .font(.manrope(12))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 24)

                if let message {
                    Text(message)
                        .font(.manrope(12))
                        .foregroundStyle(ThemePalette.amber)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                        .padding(.bottom, 16)
                }

                Button(action: isShort ? { showTopUp = true } : pay) {
                    HStack(spacing: 8) {
                        if isPaying {
                            ProgressView().tint(.white).controlSize(.small)
                            Text("Unlocking...")
                        } else {
                            Text(isShort ? "TOP UP TO UNLOCK" : "UNLOCK")
                        }
                    }
                    .font(.manrope(13, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: [ThemePalette.amber, ThemePalette.amberDeep],
                                       startPoint: .leading, endPoint: .trailing),
                        in: Capsule()
                    )
                    .shadow(color: ThemePalette.amber.opacity(0.2), radius: 10, y: 4)
                    .opacity(isPaying ? 0.5 : 1)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isPaying)

                Button("CANCEL", action: onClose)
                    .font(.manrope(11, weight: .medium))
                    .kerning(1.2)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 24)
                    .disabled(isPaying)
            }
        } onBackdropTap: {
            if !isPaying { onClose() }
        }
        .sheet(isPresented: $showTopUp) {
            TopUpSheet()
                .environment(credits)
        }
    }

    private func pay() {
        guard !isPaying else { return }
        isPaying = true
        message = nil
        Task {
            defer { isPaying = false }
            do {
                let result = try await CreditsAPI.purchaseEntitlement(key: theme.priceKey)
                if result.ok {
                    onUnlocked()
                } else if result.isInsufficientCredits {
                    await credits.refresh()
                    message = "You need \(TopUpStyle.count(result.shortBy ?? 0)) more credits."
                } else if result.error == "NOT_VERIFIED" {
                    message = "Your store needs to be verified before you can unlock themes."
                } else {
                    message = "This theme can't be unlocked right now. Please try again."
                }
            } catch {
                // The charge may have landed; a retry replays it rather than repeating it.
                message = "Couldn't reach the server. Try again — you won't be charged twice."
            }
        }
    }
}

// MARK: - Claim

/// CLAIM → "Applying Theme…" → "Success!", then the theme is applied — the
/// web's `ClaimModal`, including its one-second and 1.5-second beats.
private struct ClaimThemeSheet: View {
    let theme: ThemeOption
    let onClose: () -> Void
    let onClaimed: () -> Void

    @State private var isClaiming = false
    @State private var isSuccess = false

    var body: some View {
        ThemeSheetScaffold(theme: theme, imageOpacity: 0.8) {
            VStack(spacing: 0) {
                Text("✦ ✦ ✦")
                    .font(.manrope(14))
                    .kerning(6)
                    .foregroundStyle(ThemePalette.amber)
                    .padding(.bottom, 20)

                if isSuccess {
                    success
                } else {
                    claim
                }
            }
            .animation(Motion.fadeIn, value: isSuccess)
        } onBackdropTap: {
            if !isClaiming && !isSuccess { onClose() }
        }
    }

    private var claim: some View {
        VStack(spacing: 0) {
            Text("Claim your palatial theme experience")
                .font(.cirka(24))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.bottom, 16)

            Rectangle()
                .fill(ThemePalette.amber.opacity(0.5))
                .frame(width: 32, height: 1)
                .padding(.bottom, 24)

            Text("Unlock premium components, custom layouts, and a royal theme tailored for your store.")
                .font(.manrope(12.5))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
                .padding(.bottom, 32)

            Button(action: startClaim) {
                HStack(spacing: 8) {
                    if isClaiming {
                        ProgressView().tint(.white).controlSize(.small)
                        Text("Applying Theme...")
                    } else {
                        Text("CLAIM")
                    }
                }
                .font(.manrope(13, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(colors: [ThemePalette.amber, ThemePalette.amberDeep],
                                   startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
                .shadow(color: ThemePalette.amber.opacity(0.2), radius: 10, y: 4)
                .opacity(isClaiming ? 0.5 : 1)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isClaiming)

            Button("CANCEL", action: onClose)
                .font(.manrope(11, weight: .medium))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 24)
                .disabled(isClaiming)
        }
    }

    private var success: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(ThemePalette.emerald.opacity(0.1))
                    .frame(width: 64, height: 64)
                    .overlay { Circle().stroke(ThemePalette.emerald.opacity(0.3), lineWidth: 1) }
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(ThemePalette.emerald)
            }
            .padding(.bottom, 24)

            Text("Success!")
                .font(.manrope(18, weight: .semibold))
                .foregroundStyle(ThemePalette.emerald)
                .padding(.bottom, 8)

            Text("\(theme.name) theme applied successfully")
                .font(.manrope(15, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .transition(.opacity)
    }

    private func startClaim() {
        guard !isClaiming else { return }
        isClaiming = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            isClaiming = false
            isSuccess = true
            try? await Task.sleep(for: .milliseconds(1500))
            onClaimed()
        }
    }
}

// MARK: - Shared sheet chrome

/// The card both sheets sit in: the theme's own artwork behind a dark
/// gradient, 340pt wide, dimmed blurred backdrop.
private struct ThemeSheetScaffold<Content: View>: View {
    let theme: ThemeOption
    var imageOpacity: Double
    @ViewBuilder var content: Content
    var onBackdropTap: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: onBackdropTap)

            ZStack {
                CachedImage(url: theme.imageURL)
                    .opacity(imageOpacity)
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.95), location: 0),
                                .init(color: .black.opacity(0.5), location: 0.4),
                                .init(color: .black.opacity(0.2), location: 1)
                            ],
                            startPoint: .bottom, endPoint: .top
                        )
                    }

                content
                    .padding(.horizontal, 32)
                    .padding(.top, 56)
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: 340)
            .frame(minHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
            .clipShape(.rect(cornerRadius: 24))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
            .padding(.horizontal, 16)
        }
    }
}
