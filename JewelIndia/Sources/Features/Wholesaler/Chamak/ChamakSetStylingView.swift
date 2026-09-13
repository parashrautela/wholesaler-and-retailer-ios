import SwiftUI

/// Set Creation's counterpart to `ChamakSliderFormView` — structurally the
/// same header/scroll/bottom-bar shell, but replaces the attribute sliders
/// (meaningless here — nothing is being blended) with a backdrop picker.
/// Copy and layout match the web app's `SetCreationStyleStep.jsx` exactly:
/// no AI analysis report (Set Creation skips that stage entirely), no
/// compiled-prompt display, just the two chosen pieces, 4 backdrop presets,
/// and an optional staging note.
struct ChamakSetStylingView: View {
    @Environment(CreditStore.self) private var credits
    @Bindable var vm: ChamakViewModel
    let wholesalerID: UUID

    private let noteLimit = 400

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    comparisonHeader
                    backdropSection
                    stylingChipsSection
                    notesSection
                }
                .padding(.horizontal, Spacing.base)
                .padding(.top, Spacing.base)
                .padding(.bottom, Spacing.huge)
            }
            .scrollIndicators(.hidden)

            bottomActionBar
        }
        .background(Color(hex: 0xFAFAFA))
        .sheet(isPresented: $vm.showInsufficientCreditsSheet) {
            InsufficientCreditsSheet(error: vm.insufficientCreditsError)
                .presentationDetents([.medium])
        }
    }

    private var stylingChipsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Quick styling").font(.manrope(13, weight: .bold)).foregroundStyle(Palette.dark)
                Spacer()
                Text("Optional").font(.manrope(11)).foregroundStyle(Palette.muted)
            }
            Text("Choose any options to guide the composition. Your jewelry stays unchanged.")
                .font(.manrope(11)).foregroundStyle(Palette.muted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(SetStylingChip.all) { chip in
                    let selected = vm.selectedStylingChips.contains(chip)
                    Button { vm.toggleStylingChip(chip) } label: {
                        HStack(spacing: 6) {
                            if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                            Text(chip.label).lineLimit(1)
                        }
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(selected ? .white : Palette.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(selected ? Color(hex: 0x111827) : Color(hex: 0xF9FAFB), in: Capsule())
                        .overlay { Capsule().stroke(selected ? Color.clear : Color(hex: 0xE5E7EB), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.base)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE5E7EB), lineWidth: 1) }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button {
                vm.resetToPicker()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Change Pieces")
                }
                .font(.manrope(13, weight: .medium))
                .foregroundStyle(Palette.dark)
            }

            Spacer()

            Text("Set Styling")
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

    // MARK: - Comparison Header

    private var comparisonHeader: some View {
        HStack(spacing: Spacing.md) {
            pieceThumbnail(label: "Piece 1", design: vm.selectedDesign1, accentColor: Color(hex: 0xD4AF37))

            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: 0xBB8651))

            pieceThumbnail(label: "Piece 2", design: vm.selectedDesign2, accentColor: Color(hex: 0x3B82F6))
        }
        .padding(Spacing.base)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private func pieceThumbnail(label: String, design: ChamakDesignItem?, accentColor: Color) -> some View {
        VStack(spacing: 4) {
            Group {
                if let data = design?.localImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else if let url = design?.displayURL(.card) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color(hex: 0xF3F4F6)
                    }
                } else {
                    Color(hex: 0xF3F4F6)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(.rect(cornerRadius: 8))

            Text(label)
                .font(.manrope(11, weight: .bold))
                .foregroundStyle(accentColor)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Backdrop Section

    private var backdropSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Choose a Backdrop")
                .font(.cirka(18, weight: .medium))
                .foregroundStyle(Palette.dark)

            // Two across on a phone, all four in one row on an iPad.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.sm)],
                spacing: Spacing.sm
            ) {
                ForEach(SetBackdrop.allCases, id: \.self) { backdrop in
                    backdropCard(backdrop)
                }
            }
        }
        .padding(Spacing.base)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private func backdropCard(_ backdrop: SetBackdrop) -> some View {
        let isSelected = vm.selectedBackdrop == backdrop

        return Button {
            vm.selectedBackdrop = backdrop
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(swatch(for: backdrop))
                    .frame(height: 44)

                Text(backdrop.label)
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Palette.dark)

                Text(backdrop.blurb)
                    .font(.manrope(10))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color(hex: 0xFFFBF4) : Color(hex: 0xF9FAFB), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color(hex: 0xBB8651) : Color(hex: 0xE5E7EB), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    /// Flat gradient standing in for the web's CSS swatches
    /// (`SetCreationStyleStep.jsx`) — no image asset needed per preset.
    private func swatch(for backdrop: SetBackdrop) -> LinearGradient {
        let colors: [Color]
        switch backdrop {
        case .velvetBust: colors = [Color(hex: 0x0F4C4C), Color(hex: 0x6B1F2A)]
        case .darkSlate: colors = [Color(hex: 0x2B2B2B), Color(hex: 0x4A4A4A)]
        case .festive: colors = [Color(hex: 0x6B1F2A), Color(hex: 0xD4AF37)]
        case .cleanStudio: colors = [Color(hex: 0xE5E5E5), Color(hex: 0xF5F5F5)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Staging Note (Optional)")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Palette.dark)
                Spacer()
                Text("\(vm.noteText.count)/\(noteLimit)")
                    .font(.manrope(10))
                    .foregroundStyle(Palette.muted)
            }

            TextField(
                "e.g. warmer lighting, place the earrings slightly higher",
                text: Binding(
                    get: { vm.noteText },
                    set: { vm.noteText = String($0.prefix(noteLimit)) }
                ),
                axis: .vertical
            )
            .lineLimit(3...5)
            .font(.manrope(13))
            .padding(Spacing.md)
            .background(Color(hex: 0xF9FAFB), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }

            Text("This affects the backdrop, arrangement and lighting only — it will not change either piece of jewellery.")
                .font(.manrope(11))
                .foregroundStyle(Palette.muted)
        }
        .padding(Spacing.base)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        let cost = credits.cost(for: "chamak.set_creation")

        return VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set Creation")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Palette.dark)

                    if let wallet = credits.wallet {
                        Text("\(wallet.available) credits available in Treasure Chest")
                            .font(.manrope(11))
                            .foregroundStyle(Palette.muted)
                    } else {
                        Text("AI Set Staging")
                            .font(.manrope(11))
                            .foregroundStyle(Palette.muted)
                    }
                }

                Spacer()

                Button {
                    Task {
                        await vm.submitSetAndGenerate(wholesalerID: wholesalerID, creditStore: credits)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        if let cost, cost > 0 {
                            Text("Create Set · \(cost) credits")
                        } else {
                            Text("Create Set")
                        }
                    }
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color(hex: 0x111827), in: .rect(cornerRadius: 10))
                }
                .disabled(vm.isSubmitting)
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.md)
            .background(Color.white)
        }
    }
}
