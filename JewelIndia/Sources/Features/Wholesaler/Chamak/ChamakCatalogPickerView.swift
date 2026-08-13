import SwiftUI

struct ChamakCatalogPickerView: View {
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
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    selectionSlotsSection
                    quotaBanner
                    catalogGridSection
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Chamak AI Fusion")
                    .font(.cirka(24, weight: .bold))
                    .foregroundStyle(Palette.dark)
                Text("Select 2 catalogue designs to generate a fused masterpiece")
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)
            }

            Spacer()

            Button {
                vm.step = .gallery
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 14))
                    Text("Gallery")
                        .font(.manrope(13, weight: .semibold))
                }
                .foregroundStyle(Color(hex: 0xBB8651))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: 0xBB8651).opacity(0.1), in: .capsule)
            }
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.md)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Selection Slots

    private var selectionSlotsSection: some View {
        HStack(spacing: Spacing.md) {
            // Slot 1: High Performing
            selectionCard(
                title: "Design 1 (Strong)",
                subtitle: "Source of core strengths",
                product: vm.selectedDesign1,
                accentColor: Color(hex: 0xD4AF37),
                isDesign1: true
            )

            // Fusion icon
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.muted)

            // Slot 2: Low Performing
            selectionCard(
                title: "Design 2 (Upgrade)",
                subtitle: "Attributes to replace",
                product: vm.selectedDesign2,
                accentColor: Color(hex: 0x3B82F6),
                isDesign1: false
            )
        }
    }

    private func selectionCard(
        title: String,
        subtitle: String,
        product: Product?,
        accentColor: Color,
        isDesign1: Bool
    ) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(title)
                .font(.manrope(12, weight: .bold))
                .foregroundStyle(accentColor)

            ZStack {
                if let product, let urlString = product.processedImageURL ?? product.imageURL ?? product.rawImageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Color(hex: 0xF3F4F6)
                            .overlay(ProgressView())
                    }
                    .frame(height: 110)
                    .clipShape(.rect(cornerRadius: 10))

                    // Remove button
                    Button {
                        if isDesign1 {
                            vm.selectedDesign1 = nil
                        } else {
                            vm.selectedDesign2 = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, Color.black.opacity(0.6))
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            accentColor.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                        .background(accentColor.opacity(0.04), in: .rect(cornerRadius: 10))
                        .frame(height: 110)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: isDesign1 ? "star.fill" : "arrow.triangle.2.circlepath")
                                    .font(.system(size: 20))
                                    .foregroundStyle(accentColor)
                                Text("Tap below")
                                    .font(.manrope(11))
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                }
            }

            Text(product?.title ?? subtitle)
                .font(.manrope(11))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.sm)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    // MARK: - Quota Banner

    private var quotaBanner: some View {
        HStack {
            Image(systemName: "bolt.badge.clock.fill")
                .foregroundStyle(Color(hex: 0xBB8651))
            Text("Daily Chamak AI Quota:")
                .font(.manrope(13, weight: .medium))
                .foregroundStyle(Palette.dark)
            Spacer()
            Text("\(vm.remainingQuota)/\(vm.totalQuota) remaining")
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(vm.isQuotaExhausted ? Color.red : Color(hex: 0xBB8651))
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.sm)
        .background(Color(hex: 0xFFFBF4), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: 0xF3E8D6), lineWidth: 1)
        }
    }

    // MARK: - Catalog Grid

    private var catalogGridSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Your Catalogue Items")
                .font(.cirka(18, weight: .medium))
                .foregroundStyle(Palette.dark)

            if vm.isLoadingProducts {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else if vm.catalogProducts.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36))
                        .foregroundStyle(Palette.muted)
                    Text("No products with images found in your catalogue.")
                        .font(.manrope(14))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(vm.catalogProducts) { product in
                        productCard(product)
                    }
                }
            }
        }
    }

    private func productCard(_ product: Product) -> some View {
        let isSlot1 = vm.selectedDesign1?.id == product.id
        let isSlot2 = vm.selectedDesign2?.id == product.id
        let isSelected = isSlot1 || isSlot2

        return Button {
            vm.selectProduct(product)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ZStack(alignment: .topTrailing) {
                    if let urlString = product.processedImageURL ?? product.imageURL ?? product.rawImageURL,
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color(hex: 0xF3F4F6)
                        }
                        .frame(height: 140)
                        .clipShape(.rect(cornerRadius: 8))
                    } else {
                        Color(hex: 0xF3F4F6)
                            .frame(height: 140)
                            .clipShape(.rect(cornerRadius: 8))
                    }

                    if isSlot1 {
                        badgeView(text: "Design 1", color: Color(hex: 0xD4AF37))
                    } else if isSlot2 {
                        badgeView(text: "Design 2", color: Color(hex: 0x3B82F6))
                    }
                }

                Text(product.title ?? "Untitled Design")
                    .font(.manrope(13, weight: .medium))
                    .foregroundStyle(Palette.dark)
                    .lineLimit(1)

                HStack {
                    if let type = product.jewelleryType {
                        Text(type.capitalized)
                            .font(.manrope(11))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    if let purity = product.metalPurity {
                        Text(purity.uppercased())
                            .font(.manrope(11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x92400E))
                    }
                }
            }
            .padding(Spacing.sm)
            .background(Color.white, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSlot1 ? Color(hex: 0xD4AF37) : (isSlot2 ? Color(hex: 0x3B82F6) : Color(hex: 0xE5E7EB)),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(isSelected ? 0.08 : 0.02), radius: 4, y: 2)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func badgeView(text: String, color: Color) -> some View {
        Text(text)
            .font(.manrope(10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: .capsule)
            .padding(6)
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.canStartAnalysis ? "Ready for AI Analysis" : "Select 2 distinct designs")
                        .font(.manrope(13, weight: .semibold))
                        .foregroundStyle(vm.canStartAnalysis ? Palette.dark : Palette.muted)
                    Text("Stage 1: AI Vision Assessment")
                        .font(.manrope(11))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                Button {
                    Task {
                        await vm.startVisionAnalysis(wholesalerID: wholesalerID)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Analyze")
                    }
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        vm.canStartAnalysis ? Color.black : Color(hex: 0x9CA3AF),
                        in: .rect(cornerRadius: 10)
                    )
                }
                .disabled(!vm.canStartAnalysis)
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.md)
            .background(Color.white)
        }
    }
}
