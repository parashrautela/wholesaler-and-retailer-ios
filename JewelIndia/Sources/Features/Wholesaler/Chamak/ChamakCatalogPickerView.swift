import PhotosUI
import SwiftUI

struct ChamakCatalogPickerView: View {
    @Environment(CreditStore.self) private var credits
    @Bindable var vm: ChamakViewModel
    let wholesalerID: UUID

    @State private var photoItemSlot1: PhotosPickerItem?
    @State private var photoItemSlot2: PhotosPickerItem?
    @State private var showPickError = false

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    selectionSlotsSection
                    creditBalanceBanner
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
        .sheet(isPresented: $vm.showInsufficientCreditsSheet) {
            InsufficientCreditsSheet(error: vm.insufficientCreditsError)
                .presentationDetents([.medium])
        }
        .onChange(of: photoItemSlot1) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let jpeg = ImageNormalizer.jpeg(from: data, maxDimension: ImageNormalizer.maxProductDimension) else {
                    showPickError = true
                    photoItemSlot1 = nil
                    return
                }
                vm.setCustomImage(data: jpeg, forSlot: 1)
                photoItemSlot1 = nil
            }
        }
        .onChange(of: photoItemSlot2) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let jpeg = ImageNormalizer.jpeg(from: data, maxDimension: ImageNormalizer.maxProductDimension) else {
                    showPickError = true
                    photoItemSlot2 = nil
                    return
                }
                vm.setCustomImage(data: jpeg, forSlot: 2)
                photoItemSlot2 = nil
            }
        }
        .alert("Photo Couldn't Be Loaded", isPresented: $showPickError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("That photo couldn't be loaded — please try a different image.")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.mode == .setCreation ? "Set Creation" : "Chamak AI Fusion")
                        .font(.cirka(24, weight: .bold))
                        .foregroundStyle(Palette.dark)
                    Text(
                        vm.mode == .setCreation
                            ? "Choose 2 pieces to stage together as a matched set"
                            : "Choose 2 catalogue designs or upload custom photos"
                    )
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

            modeToggle
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.md)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeToggleButton(title: "Fuse Designs", mode: .fusion)
            modeToggleButton(title: "Set Creation", mode: .setCreation)
        }
        .padding(3)
        .background(Color(hex: 0xF3F4F6), in: .capsule)
    }

    private func modeToggleButton(title: String, mode: ChamakMode) -> some View {
        let isSelected = vm.mode == mode
        return Button {
            vm.mode = mode
        } label: {
            Text(title)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Palette.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color(hex: 0x111827) : Color.clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection Slots

    private var selectionSlotsSection: some View {
        HStack(spacing: Spacing.md) {
            selectionCard(
                slotNumber: 1,
                title: vm.mode == .setCreation ? "Piece 1" : "Design 1 (Strong)",
                subtitle: vm.mode == .setCreation ? "e.g. the necklace" : "Core strengths to keep",
                designItem: vm.selectedDesign1,
                accentColor: Color(hex: 0xD4AF37)
            )

            VStack {
                Image(systemName: vm.mode == .setCreation ? "sparkles" : "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0xBB8651))
                    .padding(8)
                    .background(Color(hex: 0xFFFBF4), in: .circle)
                    .overlay {
                        Circle().stroke(Color(hex: 0xF3E8D6), lineWidth: 1)
                    }
            }

            selectionCard(
                slotNumber: 2,
                title: vm.mode == .setCreation ? "Piece 2" : "Design 2 (Upgrade)",
                subtitle: vm.mode == .setCreation ? "e.g. the earrings" : "Attributes to replace",
                designItem: vm.selectedDesign2,
                accentColor: Color(hex: 0x3B82F6)
            )
        }
    }

    private func selectionCard(
        slotNumber: Int,
        title: String,
        subtitle: String,
        designItem: ChamakDesignItem?,
        accentColor: Color
    ) -> some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text(title)
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(accentColor)
                Spacer()
                if designItem != nil {
                    Button {
                        if slotNumber == 1 {
                            vm.selectedDesign1 = nil
                        } else {
                            vm.selectedDesign2 = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }

            ZStack {
                if let design = designItem {
                    designPreview(design: design)
                        .frame(height: 120)
                        .clipShape(.rect(cornerRadius: 10))
                } else {
                    emptySlotPlaceholder(slotNumber: slotNumber, subtitle: subtitle, accentColor: accentColor)
                        .frame(height: 120)
                }
            }

            Text(designItem?.title ?? subtitle)
                .font(.manrope(11, weight: designItem != nil ? .semibold : .regular))
                .foregroundStyle(designItem != nil ? Palette.dark : Palette.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.sm)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    designItem != nil ? accentColor.opacity(0.8) : Color(hex: 0xE5E7EB),
                    lineWidth: designItem != nil ? 1.5 : 1
                )
        }
    }

    @ViewBuilder
    private func designPreview(design: ChamakDesignItem) -> some View {
        if let localData = design.localImageData, let uiImage = UIImage(data: localData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let urlStr = design.imageURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color(hex: 0xF3F4F6)
                    .overlay(ProgressView())
            }
        } else {
            Color(hex: 0xF3F4F6)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(Palette.muted)
                }
        }
    }

    private func emptySlotPlaceholder(slotNumber: Int, subtitle: String, accentColor: Color) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(
                accentColor.opacity(0.5),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
            .background(accentColor.opacity(0.04), in: .rect(cornerRadius: 10))
            .overlay {
                VStack(spacing: 6) {
                    PhotosPicker(
                        selection: slotNumber == 1 ? $photoItemSlot1 : $photoItemSlot2,
                        matching: .images
                    ) {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11))
                            Text("Upload Photo")
                                .font(.manrope(11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accentColor, in: .capsule)
                    }

                    Text("or tap catalogue below")
                        .font(.manrope(10))
                        .foregroundStyle(Palette.muted)
                }
            }
    }

    // MARK: - Credit Balance Banner

    private var creditBalanceBanner: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(Color(hex: 0xBB8651))
            Text("Treasure Chest Wallet:")
                .font(.manrope(13, weight: .medium))
                .foregroundStyle(Palette.dark)
            Spacer()
            if let wallet = credits.wallet {
                Text("\(wallet.available) credits available")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(wallet.lowBalance ? Palette.statusPending : Color(hex: 0xBB8651))
            } else {
                Text("Loading...")
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)
            }
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
            HStack {
                Text("Pick from Catalogue")
                    .font(.cirka(18, weight: .medium))
                    .foregroundStyle(Palette.dark)
                Spacer()
                if !vm.catalogProducts.isEmpty {
                    Text("\(vm.catalogProducts.count) items")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                }
            }

            if vm.isLoadingProducts {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else if vm.catalogProducts.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(hex: 0xBB8651))
                    Text("No catalogue items found")
                        .font(.manrope(14, weight: .semibold))
                        .foregroundStyle(Palette.dark)
                    Text(
                        vm.mode == .setCreation
                            ? "Upload photos directly using the buttons in the Piece 1 and Piece 2 slots above."
                            : "Upload photos directly using the buttons in Design 1 and Design 2 slots above."
                    )
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(Color.white, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
                }
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
        let isSlot1 = vm.selectedDesign1?.product?.id == product.id
        let isSlot2 = vm.selectedDesign2?.product?.id == product.id
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
                        badgeView(text: vm.mode == .setCreation ? "Piece 1" : "Design 1", color: Color(hex: 0xD4AF37))
                    } else if isSlot2 {
                        badgeView(text: vm.mode == .setCreation ? "Piece 2" : "Design 2", color: Color(hex: 0x3B82F6))
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

    private var readyLabel: String {
        vm.mode == .setCreation ? "Ready to Style Your Set" : "Ready for AI Analysis"
    }

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.canStartAnalysis ? readyLabel : "Select or upload 2 designs")
                        .font(.manrope(13, weight: .semibold))
                        .foregroundStyle(vm.canStartAnalysis ? Palette.dark : Palette.muted)
                    Text(vm.mode == .setCreation ? "Next: choose a backdrop" : "Stage 1: AI Vision Assessment")
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
                        Text(vm.mode == .setCreation ? "Choose Backdrop" : "Analyze")
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
