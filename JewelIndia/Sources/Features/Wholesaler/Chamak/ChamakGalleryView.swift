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
                if vm.galleryGenerations.isEmpty {
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
        }
        .background(Color(hex: 0xFAFAFA))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button {
                vm.step = .catalogPicker
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("New Fusion")
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
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color(hex: 0xF3F4F6)
                        }
                        .frame(height: 150)
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

                HStack {
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
