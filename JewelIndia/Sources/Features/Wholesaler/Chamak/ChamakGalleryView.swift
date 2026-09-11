import SwiftUI

struct ChamakGalleryView: View {
    @Bindable var vm: ChamakViewModel
    let wholesalerID: UUID

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                // A failed read and an empty account are different situations
                // and must not share the same screen: the empty state invites
                // you to make your first generation, which is actively
                // misleading copy to show someone whose generations exist but
                // could not be fetched.
                if let message = vm.galleryErrorMessage, vm.galleryGenerations.isEmpty {
                    errorState(message)
                } else if vm.galleryGenerations.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: ChamakHubView.galleryColumns, spacing: Spacing.md) {
                        ForEach(vm.galleryGenerations) { gen in
                            ChamakGalleryCard(
                                generation: gen,
                                thumbnailURL: vm.galleryThumbnailURLs[gen.id]
                            ) {
                                Task { await vm.openGalleryItem(gen) }
                            }
                        }
                    }
                    .padding(Spacing.base)
                }
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await vm.refreshGallery(wholesalerID: wholesalerID)
            }
        }
        .background(Color(hex: 0xFAFAFA))
        .task {
            // `ChamakFlowCoordinator` loads the gallery once per presentation,
            // so anything generated during this session is absent until the
            // flow is dismissed. Re-read on entry instead.
            await vm.refreshGallery(wholesalerID: wholesalerID)
        }
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: 0xD97706).opacity(0.8))

            Text("Couldn't Load Your Gallery")
                .font(.cirka(20, weight: .bold))
                .foregroundStyle(Palette.dark)

            Text(message)
                .font(.manrope(13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Button {
                Task { await vm.refreshGallery(wholesalerID: wholesalerID) }
            } label: {
                Group {
                    if vm.isRefreshingGallery {
                        ProgressView().tint(.white)
                    } else {
                        Text("Try Again")
                            .font(.manrope(14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Palette.dark, in: .rect(cornerRadius: 8))
            }
            .disabled(vm.isRefreshingGallery)
            .padding(.top, Spacing.sm)
        }
        .padding(Spacing.xxxl)
        .frame(maxWidth: .infinity, minHeight: 350)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button {
                vm.step = .catalogPicker
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)
            }

            Spacer()

            Text("Chamak Gallery")
                .font(.cirka(18, weight: .bold))
                .foregroundStyle(Palette.dark)

            Spacer()

            Color.clear.frame(width: 80, height: 10)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.md)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: 0xBB8651).opacity(0.7))

            Text("No Chamak Generations Yet")
                .font(.cirka(20, weight: .bold))
                .foregroundStyle(Palette.dark)

            Text("Fuse your first pair of catalogue designs to see your AI creations stored here.")
                .font(.manrope(13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Button {
                vm.step = .catalogPicker
            } label: {
                Text("Start Fusion")
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Palette.dark, in: .rect(cornerRadius: 8))
            }
            .padding(.top, Spacing.sm)
        }
        .padding(Spacing.xxxl)
        .frame(maxWidth: .infinity, minHeight: 350)
    }
}
