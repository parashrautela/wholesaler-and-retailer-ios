import SwiftUI

struct ChamakSliderFormView: View {
    @Environment(CreditStore.self) private var credits
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var vm: ChamakViewModel
    let wholesalerID: UUID

    @State private var previewImageURL: URL?
    @State private var showAiReportDetails = false
    @State private var selectedChipIDs: [String] = []

    private var analysis: Stage1Analysis? {
        vm.currentGeneration?.stage1AnalysisJSON
    }

    private var isHardBlocked: Bool {
        if let flag = analysis?.contentFlag, flag != .ok {
            return true
        }
        return false
    }

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                Group {
                    if isRegularWidth {
                        HStack(alignment: .top, spacing: Spacing.lg) {
                            VStack(alignment: .leading, spacing: Spacing.lg) {
                                comparisonCards
                                contentFlagBanner
                                warningBanners
                                aiReportCard
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: Spacing.lg) {
                                fineTuneSlidersCard
                                customizationNoteCard
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            comparisonCards
                            contentFlagBanner
                            warningBanners
                            aiReportCard
                            fineTuneSlidersCard
                            customizationNoteCard
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
                ChamakViewerImage(id: "preview", label: "Design Preview", url: item.url, isResult: false)
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

            Text("Design Harmony")
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

    // MARK: - Comparison Cards

    private var comparisonCards: some View {
        HStack(spacing: Spacing.md) {
            designThumbnailCard(
                title: vm.selectedDesign1?.title ?? "Core design",
                subtitle: "Keeps its identity",
                design: vm.selectedDesign1,
                accentColor: Color(hex: 0xCA8A04)
            )

            designThumbnailCard(
                title: vm.selectedDesign2?.title ?? "New direction",
                subtitle: "New expression",
                design: vm.selectedDesign2,
                accentColor: Color(hex: 0x3B82F6)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func designThumbnailCard(
        title: String,
        subtitle: String,
        design: ChamakDesignItem?,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color(hex: 0xF3F4F6)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let data = design?.localImageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        } else if let url = design?.displayURL(.card) {
                            ProtectedImageView(url: url)
                        } else {
                            Color(hex: 0xF3F4F6)
                        }
                    }
                    .clipped()

                if let url = design?.displayURL(.full) ?? design?.displayURL(.card) {
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
                Text(title)
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Palette.dark)
                    .lineLimit(1)
                Text(subtitle)
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

    // MARK: - AI Report Card

    private var aiReportCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Ai Report")
                    .font(.manrope(16, weight: .bold))
                    .foregroundStyle(Palette.dark)

                Spacer()

                Menu {
                    Button("Details") { showAiReportDetails.toggle() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0x5E5D5A))
                        .padding(4)
                }
            }

            HStack(alignment: .top, spacing: Spacing.md) {
                // Column 1: Design 1 Strengths
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.selectedDesign1?.title ?? "Core design")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Color(hex: 0xCA8A04))
                        .lineLimit(1)

                    let list1 = analysis?.image1Strengths ?? defaultStrengths1
                    ForEach(list1.prefix(5), id: \.self) { item in
                        HStack(alignment: .top, spacing: 5) {
                            Text("•").font(.manrope(12, weight: .bold)).foregroundStyle(Palette.muted)
                            Text(item.capitalized)
                                .font(.manrope(12))
                                .foregroundStyle(Color(hex: 0x4B5563))
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Column 2: Design 2 Strengths
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.selectedDesign2?.title ?? "New direction")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x3B82F6))
                        .lineLimit(1)

                    let list2 = analysis?.image2Strengths ?? defaultStrengths2
                    ForEach(list2.prefix(5), id: \.self) { item in
                        HStack(alignment: .top, spacing: 5) {
                            Text("•").font(.manrope(12, weight: .bold)).foregroundStyle(Palette.muted)
                            Text(item.capitalized)
                                .font(.manrope(12))
                                .foregroundStyle(Color(hex: 0x4B5563))
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var defaultStrengths1: [String] {
        ["Intricate floral motifs", "Vibrant gemstone colors", "Balanced symmetry", "Elegant gold finish", "Lightweight design"]
    }

    private var defaultStrengths2: [String] {
        ["Intricate floral motifs", "Vibrant gemstone colors", "Balanced symmetry", "Elegant gold finish", "Lightweight design"]
    }

    // MARK: - Fine Tune Sliders Card

    private var fineTuneSlidersCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Fine Tune")
                    .font(.manrope(16, weight: .bold))
                    .foregroundStyle(Palette.dark)
                Spacer()
            }

            HStack {
                Text(vm.selectedDesign1?.title ?? "Core design")
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(Color(hex: 0xCA8A04))
                    .lineLimit(1)
                Spacer()
                Text(vm.selectedDesign2?.title ?? "New direction")
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x3B82F6))
                    .lineLimit(1)
            }
            .padding(.bottom, 2)

            let attributes = analysis?.dynamicAttributes ?? fallbackAttributes
            ForEach(attributes) { attr in
                attributeSliderRow(attr: attr)
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

    private func attributeSliderRow(attr: ChamakAttribute) -> some View {
        let binding = Binding<Double>(
            get: { vm.sliderValues[attr.id] ?? attr.defaultValue },
            set: { vm.sliderValues[attr.id] = $0 }
        )
        let val = binding.wrappedValue
        let p1 = Int(round((1.0 - val) * 100))
        let p2 = Int(round(val * 100))

        return VStack(alignment: .leading, spacing: 6) {
            Text(attr.name)
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)

            HStack(spacing: 12) {
                Text("\(p1)%")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 32, alignment: .trailing)

                Slider(value: binding, in: 0.0...1.0)
                    .tint(Color(hex: 0xCA8A04))

                Text("\(p2)%")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 32, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private var fallbackAttributes: [ChamakAttribute] {
        [
            ChamakAttribute(id: "attr_0", name: "Floral Motifs", source1Feature: "Motif", source2Feature: "Motif", defaultValue: 0.3),
            ChamakAttribute(id: "attr_1", name: "Gemstone Colors", source1Feature: "Gemstone", source2Feature: "Gemstone", defaultValue: 0.3),
            ChamakAttribute(id: "attr_2", name: "Symmetry", source1Feature: "Symmetry", source2Feature: "Symmetry", defaultValue: 0.3),
            ChamakAttribute(id: "attr_3", name: "Gold Finish", source1Feature: "Finish", source2Feature: "Finish", defaultValue: 0.3)
        ]
    }

    // MARK: - Customization Note Card

    private var availableArtisanChips: [ArtisanChip] {
        let d1Name = vm.selectedDesign1?.title ?? "Core Design"
        let d2Name = vm.selectedDesign2?.title ?? "New Direction"

        var chips: [ArtisanChip] = []

        // Chip 1: Integrity of Design 2 (User's specific highlight)
        chips.append(ArtisanChip(
            id: "integrity_d2",
            title: "Integrity of \(d2Name)",
            elaboratedPrompt: "Preserve the structural integrity, balance, and proportions of \(d2Name) as the foundational silhouette, while harmoniously weaving in the signature artistry, motifs, and texture of \(d1Name)."
        ))

        // Chip 2: Heritage of Design 1
        chips.append(ArtisanChip(
            id: "heritage_d1",
            title: "Heritage of \(d1Name)",
            elaboratedPrompt: "Anchor the piece in the authentic heritage, motif geometry, and distinctive hallmark features of \(d1Name), allowing \(d2Name) to inspire elevated modern finishing details."
        ))

        // Chip 3: AI Strengths from Design 1
        if let s1 = (analysis?.image1Strengths ?? defaultStrengths1).first {
            chips.append(ArtisanChip(
                id: "strength_d1",
                title: s1.capitalized,
                elaboratedPrompt: "Accentuate the \(s1) from \(d1Name), ensuring it anchors the central focal point and surface ornamentation."
            ))
        }

        // Chip 4: AI Strengths from Design 2
        if let s2 = (analysis?.image2Strengths ?? defaultStrengths2).first {
            chips.append(ArtisanChip(
                id: "strength_d2",
                title: s2.capitalized,
                elaboratedPrompt: "Incorporate the distinctive \(s2) from \(d2Name), introducing harmonious contrast and modern luxury."
            ))
        }

        // Chip 5: 22K Handcrafted Gold
        chips.append(ArtisanChip(
            id: "gold_finish",
            title: "22K Handcrafted Gold",
            elaboratedPrompt: "Render in rich 22K yellow gold with an authentic handcrafted micro-matte luster and subtle antique patina across all metal surfaces."
        ))

        // Chip 6: Royal Filigree
        chips.append(ArtisanChip(
            id: "filigree",
            title: "Intricate Filigree Work",
            elaboratedPrompt: "Incorporate delicate royal filigree wirework, with openwork jaali detailing and finely twisted precious gold threads."
        ))

        // Chip 7: Gemstone Accents
        chips.append(ArtisanChip(
            id: "gemstones",
            title: "High-Clarity Gemstones",
            elaboratedPrompt: "Highlight vibrant, high-clarity gemstones with precise master prong settings that maximize light refraction and brilliance."
        ))

        return chips
    }

    private func handleChipTap(_ chip: ArtisanChip) {
        if let idx = selectedChipIDs.firstIndex(of: chip.id) {
            // Deselect chip
            selectedChipIDs.remove(at: idx)
        } else {
            // Limit to at most 2 chips (Point 3: "You can select just one or just two")
            if selectedChipIDs.count >= 2 {
                selectedChipIDs.removeFirst()
            }
            selectedChipIDs.append(chip.id)
        }
        rebuildNoteFromSelectedChips()
    }

    private func rebuildNoteFromSelectedChips() {
        let active = availableArtisanChips.filter { selectedChipIDs.contains($0.id) }
        vm.noteText = active.map(\.elaboratedPrompt).joined(separator: " ")
    }

    private var customizationNoteCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Artisan Customization Note (Optional)")
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(Palette.dark)

                Spacer()

                Text(selectedChipIDs.isEmpty ? "Select 1 or 2" : "\(selectedChipIDs.count)/2 selected")
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(selectedChipIDs.isEmpty ? Palette.muted : Color(hex: 0xCA8A04))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: 0xF3F4F6), in: Capsule())
            }

            // Quick suggestion chips derived from design analysis (max 2 selectable)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableArtisanChips) { chip in
                        let isSelected = selectedChipIDs.contains(chip.id)
                        Button {
                            handleChipTap(chip)
                        } label: {
                            HStack(spacing: 5) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(chip.title)
                                    .font(.manrope(11, weight: isSelected ? .bold : .medium))
                            }
                            .foregroundStyle(isSelected ? Color.white : Palette.dark)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color(hex: 0x212120) : Color(hex: 0xF3F4F6), in: Capsule())
                            .overlay {
                                if !isSelected {
                                    Capsule().stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            TextField(
                "Select chips above or write artisan guidance here...",
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

    // MARK: - Banners

    @ViewBuilder
    private var contentFlagBanner: some View {
        if let flag = analysis?.contentFlag, flag != .ok {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(hex: 0xEF4444))
                Text(flag.userMessage ?? "Unsupported image content.")
                    .font(.manrope(12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x991B1B))
            }
            .padding(Spacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xFEF2F2), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xFECACA), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var warningBanners: some View {
        if let analysis {
            if analysis.nearIdentical {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color(hex: 0xCA8A04))
                    Text("These two designs look very similar. The fusion will emphasize subtle styling details.")
                        .font(.manrope(12))
                        .foregroundStyle(Color(hex: 0x854D0E))
                }
                .padding(Spacing.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xFEFCE8), in: RoundedRectangle(cornerRadius: 12))
            }

            if analysis.typeMismatch {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color(hex: 0xCA8A04))
                    Text("Designs appear to be different jewelry types. The model will create a hybrid blend.")
                        .font(.manrope(12))
                        .foregroundStyle(Color(hex: 0x854D0E))
                }
                .padding(Spacing.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xFEFCE8), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Bottom Action Bar (Figma Node 3061:10901)

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)

            Button {
                Task {
                    await vm.submitFormAndGenerate(wholesalerID: wholesalerID, creditStore: credits)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Generate Design")
                        .font(.manrope(16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    isHardBlocked
                        ? LinearGradient(colors: [Color(hex: 0x9CA3AF), Color(hex: 0x6B7280)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color(hex: 0x4F4F4F), Color(hex: 0x232323)], startPoint: .top, endPoint: .bottom),
                    in: Capsule()
                )
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.22), radius: 8, y: 4)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isHardBlocked || vm.isSubmitting)
            .frame(maxWidth: isRegularWidth ? 640 : .infinity)
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.md)
        }
        .background(Color.white.opacity(0.96))
    }
}

// MARK: - Artisan Chip Model

struct ArtisanChip: Identifiable, Equatable {
    let id: String
    let title: String
    let elaboratedPrompt: String
}

private struct PreviewURLItem: Identifiable {
    let id = UUID()
    let url: URL
}
