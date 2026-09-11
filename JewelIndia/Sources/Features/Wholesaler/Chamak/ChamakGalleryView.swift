import SwiftUI

struct ChamakGalleryView: View {
    @Bindable var vm: ChamakViewModel
    let wholesalerID: UUID

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md)
    ]

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
                    LazyVGrid(columns: columns, spacing: Spacing.md) {
                        ForEach(vm.galleryGenerations) { gen in
                            galleryCard(gen)
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

    // MARK: - Gallery Card

    private func galleryCard(_ gen: ChamakGeneration) -> some View {
        Button {
            Task {
                await vm.openGalleryItem(gen)
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ZStack(alignment: .topTrailing) {
                    if let output = gen.outputImageURL, let url = URL(string: output) {
                        ProtectedImageView(url: url)
                            .frame(height: 150)
                            .background(Color(hex: 0xF3F4F6))
                            .clipped()
                            .clipShape(.rect(cornerRadius: 8))
                    } else {
                        Color(hex: 0xF3F4F6)
                            .frame(height: 150)
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color(hex: 0xBB8651))
                            }
                    }

                    statusBadge(status: gen.status)
                }

                HStack(spacing: 6) {
                    modeBadge(gen.mode)
                    Text(formattedDate(gen.createdAt))
                        .font(.manrope(11))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Text(gen.promptVersion)
                        .font(.manrope(10, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xBB8651))
                }
            }
            .padding(Spacing.sm)
            .background(Color.white, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.02), radius: 3, y: 1)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func modeBadge(_ mode: ChamakMode) -> some View {
        Text(mode == .setCreation ? "Set" : "Fusion")
            .font(.manrope(9, weight: .bold))
            .foregroundStyle(mode == .setCreation ? Color(hex: 0xBB8651) : Color(hex: 0x6B7280))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(mode == .setCreation ? Color(hex: 0xFFFBF4) : Color(hex: 0xF3F4F6), in: .capsule)
    }

    private func statusBadge(status: ChamakStatus) -> some View {
        let (color, text) = switch status {
        case .done: (Color(hex: 0x16A34A), "Done")
        case .generating, .analyzing, .queued: (Color(hex: 0xD97706), "Processing")
        case .awaitingInput: (Color(hex: 0x2563EB), "Input")
        case .failed: (Color(hex: 0xDC2626), "Failed")
        }

        return Text(text)
            .font(.manrope(10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: .capsule)
            .padding(6)
    }

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) {
            let display = DateFormatter()
            display.dateStyle = .medium
            return display.string(from: date)
        }
        return "Recent"
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
