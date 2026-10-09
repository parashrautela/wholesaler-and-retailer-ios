import SwiftUI

struct ChamakSetStylingView: View {
    @Environment(CreditStore.self) private var credits
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var vm: ChamakViewModel
    let wholesalerID: UUID

    @State private var previewImageURL: URL?
    private let noteLimit = 400

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                Group {
                    if isRegularWidth {
                        HStack(alignment: .top, spacing: Spacing.lg) {
                            VStack(alignment: .leading, spacing: Spacing.lg) {
                                piecesComparisonCards
                                backdropSection
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: Spacing.lg) {
                                stylingChipsSection
                                notesSection
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            piecesComparisonCards
                            backdropSection
                            stylingChipsSection
                            notesSection
                        }
                    }
                }
                .padding(.horizontal, Spacing.base)
                .padding(.top, Spacing.base)
                .padding(.bottom, 100)
                .frame(maxWidth: isRegularWidth ? 1120 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            bottomActionBar
        }
        .background(Color(hex: 0xF7F7F6))
        .sheet(isPresented: $vm.showInsufficientCreditsSheet) {
            InsufficientCreditsSheet(error: vm.insufficientCreditsError)
                .presentationDetents([.medium])
        }
        .fullScreenCover(item: Binding(
            get: { previewImageURL.map { PreviewURLItem(url: $0) } },
            set: { previewImageURL = $0?.url }
        )) { item in
            ChamakImageViewer(images: [
                ChamakViewerImage(id: "preview", label: "Piece Preview", url: item.url, isResult: false)
            ], startIndex: 0)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button {
                vm.resetToPicker()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.dark)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Text("Set Styling")
                .font(.cirka(isRegularWidth ? 26 : 22, weight: .bold))
                .foregroundStyle(Palette.dark)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: isRegularWidth ? 1120 : .infinity)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.6)
        }
    }

    // MARK: - Pieces Comparison Cards

    private var piecesComparisonCards: some View {
        let pieces = vm.setPieces
        let count = max(2, min(pieces.count, 4))

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: isRegularWidth ? count : min(2, count)),
            spacing: Spacing.md
        ) {
            ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                pieceThumbnailCard(
                    slot: index + 1,
                    label: "Piece \(index + 1)",
                    design: piece,
                    accentColor: ChamakSlot.color(for: index + 1)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pieceThumbnailCard(slot: Int, label: String, design: ChamakDesignItem, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color(hex: 0xF3F4F6)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let data = design.localImageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        } else if let url = design.displayURL(.card) {
                            ProtectedImageView(url: url)
                        } else {
                            Color(hex: 0xF3F4F6)
                        }
                    }
                    .clipped()

                if let url = design.displayURL(.full) ?? design.displayURL(.card) {
                    Button {
                        previewImageURL = url
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.dark)
                            .frame(width: 26, height: 26)
                            .background(.white.opacity(0.9), in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    }
                    .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Palette.dark)
                Text(design.title)
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xF9F9F8))
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(accentColor.opacity(0.8), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.02), radius: 4, y: 2)
    }

    // MARK: - Backdrop Presets Section

    private var backdropSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Choose Backdrop")
                .font(.manrope(16, weight: .bold))
                .foregroundStyle(Palette.dark)

            VStack(spacing: Spacing.sm) {
                ForEach(SetBackdrop.allCases, id: \.self) { preset in
                    let isSelected = vm.selectedBackdrop == preset
                    Button {
                        vm.selectedBackdrop = preset
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Circle()
                                .fill(isSelected ? Color(hex: 0xCA8A04) : Color(hex: 0xE5E7EB))
                                .frame(width: 18, height: 18)
                                .overlay {
                                    if isSelected {
                                        Circle().fill(Color.white).frame(width: 6, height: 6)
                                    }
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.label)
                                    .font(.manrope(13, weight: .bold))
                                    .foregroundStyle(Palette.dark)
                                Text(preset.blurb)
                                    .font(.manrope(11))
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(Spacing.base)
                        .background(isSelected ? Color(hex: 0xFDF8EE) : Color(hex: 0xF9FAFB), in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSelected ? Color(hex: 0xCA8A04) : Color(hex: 0xE5E7EB), lineWidth: isSelected ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.base)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0xE7E5E4), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.02), radius: 6, y: 2)
    }

    // MARK: - Styling Chips Section

    private var stylingChipsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Quick Styling")
                    .font(.manrope(16, weight: .bold))
                    .foregroundStyle(Palette.dark)
                Spacer()
                Text("Optional")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }

            Text("Choose any options to guide composition. Your jewelry stays unchanged.")
                .font(.manrope(12))
                .foregroundStyle(Palette.muted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(SetStylingChip.all) { chip in
                    let isSelected = vm.selectedStylingChips.contains(chip)
                    Button {
                        vm.toggleStylingChip(chip)
                    } label: {
                        HStack(spacing: 6) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(chip.label)
                                .lineLimit(1)
                        }
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Palette.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(isSelected ? Color(hex: 0x111827) : Color(hex: 0xF9FAFB), in: Capsule())
                        .overlay {
                            Capsule().stroke(isSelected ? Color.clear : Color(hex: 0xE5E7EB), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(Spacing.base)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0xE7E5E4), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.02), radius: 6, y: 2)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Artisan Staging Note (Optional)")
                .font(.manrope(14, weight: .bold))
                .foregroundStyle(Palette.dark)

            TextField(
                "e.g. Place necklace prominent on velvet bust, earrings arranged symmetrically...",
                text: $vm.noteText,
                axis: .vertical
            )
            .lineLimit(3...5)
            .font(.manrope(13))
            .padding(Spacing.md)
            .background(Color(hex: 0xF9FAFB), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }
        }
        .padding(Spacing.base)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0xE7E5E4), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.02), radius: 6, y: 2)
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        let cost = credits.cost(for: vm.setPriceKey)

        return VStack(spacing: 0) {
            Divider().opacity(0.6)

            Button {
                Task {
                    await vm.submitSetAndGenerate(wholesalerID: wholesalerID, creditStore: credits)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))

                    if let cost, cost > 0 {
                        Text("Generate Set · \(cost) credits")
                            .font(.manrope(14, weight: .bold))
                    } else {
                        Text("Generate Set")
                            .font(.manrope(14, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(hex: 0x212120), in: Capsule())
            }
            .disabled(vm.isSubmitting)
            .frame(maxWidth: isRegularWidth ? 640 : .infinity)
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.md)
        }
        .background(.regularMaterial)
    }
}

private struct PreviewURLItem: Identifiable {
    let id = UUID()
    let url: URL
}
