import SwiftUI

/// `/dashboard/employee` — the screen a verified retailer lands on by
/// default. Mirrors `EmployeeHomeClient.jsx` + `DesignerCollectionSection`:
/// business hero with a "select view mode" card, then a shuffled grid of the
/// retailer's own curated designs.
struct EmployeeHomeView: View {
    @Environment(SessionStore.self) private var session

    @State private var model = EmployeeHomeModel()

    let onSelectTab: (EmployeeShell.EmployeeTab) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.isLoading && model.data == nil {
                    loadingState
                } else if let errorMessage = model.errorMessage, model.data == nil {
                    errorState(errorMessage)
                } else if let data = model.data {
                    hero(data)
                    designerCollection(data)
                }
            }
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(Color.white)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await model.load(session: session)
        }
        .refreshable {
            await model.load(session: session)
        }
    }

    // MARK: - Loading / error

    private var loadingState: some View {
        VStack {
            Spacer(minLength: Spacing.huge)
            ProgressView()
                .controlSize(.large)
                .tint(Palette.dark)
            Spacer(minLength: Spacing.huge)
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Spacer(minLength: Spacing.huge)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.red)
            Text(message)
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Button("Retry") {
                Task { await model.load(session: session) }
            }
            .buttonStyle(.plain)
            .font(.manrope(14, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Palette.cream, in: Capsule())
            Spacer(minLength: Spacing.huge)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero

    private func hero(_ data: EmployeeAPI.HomeData) -> some View {
        VStack(spacing: Spacing.md) {
            AsyncImage(url: data.businessLogoURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image("JewelLogo")
                    .resizable()
                    .scaledToFit()
                    .padding(18)
            }
            .frame(width: 84, height: 84)
            .background(Color.white)
            .clipShape(Circle())
            .overlay { Circle().stroke(Palette.border, lineWidth: 1) }
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

            Text(data.businessName)
                .font(.cirka(32, weight: .medium))
                .foregroundStyle(Color(hex: 0x2C1F18))
                .multilineTextAlignment(.center)

            Text("Discover designs selected with precision, blending craftsmanship and ethnic style")
                .font(.manrope(13))
                .foregroundStyle(Color(hex: 0x4A3B32))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            viewModeCard
        }
        .padding(.horizontal, Spacing.base)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.xxl)
        .frame(maxWidth: .infinity)
        .background(heroTint(for: data.backgroundVariant))
    }

    /// 4 deterministic, subtle tints standing in for the web's 4 Cloudinary
    /// SVG hero backgrounds (`AsyncImage` can't decode a remote SVG).
    private func heroTint(for variant: Int) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(hex: 0xFAF7F2), Color(hex: 0xF3E8D6)],
            [Color(hex: 0xF7F3EA), Color(hex: 0xE8DCC8)],
            [Color(hex: 0xFDFBF7), Color(hex: 0xF0E4D0)],
            [Color(hex: 0xF9F5EE), Color(hex: 0xECDFC9)],
        ]
        let colors = palettes[variant % palettes.count]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var viewModeCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("SELECT VIEW MODE")
                .font(.cirka(18))
                .tracking(1.2)
                .foregroundStyle(.white)

            VStack(spacing: Spacing.sm) {
                Button {
                    onSelectTab(.catalogue)
                } label: {
                    Text("Catalog")
                        .font(.manrope(13, weight: .bold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white, in: .rect(cornerRadius: 4))
                }

                NavigationLink {
                    ComingSoonView(
                        title: "Infinite Canvas",
                        symbol: "wand.and.stars",
                        message: "Fuse your own catalogue designs with AI here soon."
                    )
                } label: {
                    Text("Infinite Canvas")
                        .font(.manrope(12, weight: .semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.white.opacity(0.5), lineWidth: 1)
                        }
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 320)
        .aspectRatio(1, contentMode: .fit)
        .background(Color(hex: 0x1F1712), in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }

    // MARK: - Designer collection

    private func designerCollection(_ data: EmployeeAPI.HomeData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Designer Collection")
                .font(.cirka(28))
                .foregroundStyle(Palette.dark)
                .padding(.bottom, 4)

            Text("Crafted in house with the taste of our own")
                .font(.manrope(13))
                .foregroundStyle(Palette.muted)
                .padding(.bottom, Spacing.lg)

            if data.designs.isEmpty {
                Text("No designs published yet.")
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)
                    .padding(.vertical, Spacing.xl)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Spacing.lg),
                              GridItem(.flexible(), spacing: Spacing.lg)],
                    spacing: Spacing.xl
                ) {
                    ForEach(data.designs) { design in
                        DesignCard(design: design)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.base)
    }
}

private struct DesignCard: View {
    let design: EmployeeAPI.RetailerDesign

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Color(hex: 0xF8F8F8)
                if let url = design.displayImageURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color(hex: 0xF8F8F8)
                    }
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(Palette.muted)
                }
            }
            .aspectRatio(5.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(design.title?.trimmed.nilIfEmpty ?? "Untitled design")
                .font(.cirka(14))
                .foregroundStyle(Color(hex: 0x374151))
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
    }
}

// MARK: - Model

@MainActor
@Observable
final class EmployeeHomeModel {
    var data: EmployeeAPI.HomeData?
    var isLoading = true
    var errorMessage: String?

    func load(session: SessionStore) async {
        guard let user = session.user else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            data = try await EmployeeAPI.fetchHomeData(userID: user.id)
        } catch {
            errorMessage = "Couldn't load your store. Check your connection and try again."
        }
    }
}
