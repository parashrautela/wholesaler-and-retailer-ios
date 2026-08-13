import SwiftUI

struct ChamakSliderFormView: View {
    @Bindable var vm: ChamakViewModel
    let wholesalerID: UUID

    private var analysis: Stage1Analysis? {
        vm.currentGeneration?.stage1AnalysisJSON
    }

    private var isHardBlocked: Bool {
        if let flag = analysis?.contentFlag, flag != .ok {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    comparisonHeader
                    contentFlagBanner
                    warningBanners
                    sliderSection
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
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button {
                vm.resetToPicker()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Change Designs")
                }
                .font(.manrope(13, weight: .medium))
                .foregroundStyle(Palette.dark)
            }

            Spacer()

            Text("Design Balance")
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
            designThumbnail(
                label: "Design 1 (Strengths)",
                product: vm.selectedDesign1,
                accentColor: Color(hex: 0xD4AF37)
            )

            Image(systemName: "slider.horizontal.2")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: 0xBB8651))

            designThumbnail(
                label: "Design 2 (Upgrades)",
                product: vm.selectedDesign2,
                accentColor: Color(hex: 0x3B82F6)
            )
        }
        .padding(Spacing.base)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private func designThumbnail(label: String, product: Product?, accentColor: Color) -> some View {
        VStack(spacing: 4) {
            if let product, let urlString = product.processedImageURL ?? product.imageURL ?? product.rawImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color(hex: 0xF3F4F6)
                }
                .frame(width: 80, height: 80)
                .clipShape(.rect(cornerRadius: 8))
            } else {
                Color(hex: 0xF3F4F6)
                    .frame(width: 80, height: 80)
                    .clipShape(.rect(cornerRadius: 8))
            }

            Text(label)
                .font(.manrope(11, weight: .bold))
                .foregroundStyle(accentColor)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content Flag Hard Block Banner

    @ViewBuilder
    private var contentFlagBanner: some View {
        if let flag = analysis?.contentFlag, flag != .ok, let msg = flag.userMessage {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Quality Check Block")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Color.red)
                    Text(msg)
                        .font(.manrope(12))
                        .foregroundStyle(Color(hex: 0x991B1B))
                }
            }
            .padding(Spacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xFEF2F2), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: 0xFECACA), lineWidth: 1)
            }
        }
    }

    // MARK: - Soft Warning Banners

    @ViewBuilder
    private var warningBanners: some View {
        if let analysis {
            if analysis.nearIdentical {
                warningRow(
                    icon: "info.circle.fill",
                    title: "Designs are nearly identical",
                    message: "Both selected products share very similar design elements. The fused design will produce subtle variations."
                )
            }

            if analysis.typeMismatch {
                warningRow(
                    icon: "exclamationmark.triangle.fill",
                    title: "Jewelry type mismatch",
                    message: "You are combining different categories (e.g. \(analysis.jewelryType)). The AI will synthesize motifs onto the primary silhouette."
                )
            }
        }
    }

    private func warningRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: 0xD97706))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x92400E))
                Text(message)
                    .font(.manrope(11))
                    .foregroundStyle(Color(hex: 0xB45309))
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFFBEB), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: 0xFDE68A), lineWidth: 1)
        }
    }

    // MARK: - Sliders Section

    private var sliderSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Fine-Tune Feature Weights")
                .font(.cirka(18, weight: .medium))
                .foregroundStyle(Palette.dark)

            if let attributes = analysis?.dynamicAttributes, !attributes.isEmpty {
                ForEach(attributes) { attr in
                    sliderRow(attr: attr)
                }
            } else {
                // Fallback default attributes if dynamic list is empty
                sliderRow(attr: ChamakAttribute(
                    id: "overall_blend",
                    name: "Structural Harmony",
                    source1Feature: "Design 1 Geometry",
                    source2Feature: "Design 2 Aesthetics",
                    defaultValue: 0.5
                ))
            }
        }
        .padding(Spacing.base)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private func sliderRow(attr: ChamakAttribute) -> some View {
        let binding = Binding<Double>(
            get: { vm.sliderValues[attr.id] ?? attr.defaultValue },
            set: { vm.sliderValues[attr.id] = $0 }
        )

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(attr.name)
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(Palette.dark)

            Slider(value: binding, in: 0...1)
                .tint(Color(hex: 0xBB8651))

            HStack {
                Text("Design 1: \(attr.source1Feature)")
                    .font(.manrope(11))
                    .foregroundStyle(Color(hex: 0xD4AF37))
                    .lineLimit(1)
                Spacer()
                Text("Design 2: \(attr.source2Feature)")
                    .font(.manrope(11))
                    .foregroundStyle(Color(hex: 0x3B82F6))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Artisan Customization Note (Optional)")
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(Palette.dark)

            TextField(
                "e.g. Keep 22k yellow gold texture, add delicate emerald droplets at bottom edge...",
                text: $vm.noteText,
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
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fusion Generation")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Palette.dark)
                    Text("Costs 1 Chamak credit (\(vm.remainingQuota) left)")
                        .font(.manrope(11))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                Button {
                    Task {
                        await vm.submitFormAndGenerate(wholesalerID: wholesalerID)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                        Text("Fuse Designs")
                    }
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        isHardBlocked ? Color(hex: 0x9CA3AF) : Color(hex: 0x111827),
                        in: .rect(cornerRadius: 10)
                    )
                }
                .disabled(isHardBlocked || vm.isSubmitting)
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.md)
            .background(Color.white)
        }
    }
}
