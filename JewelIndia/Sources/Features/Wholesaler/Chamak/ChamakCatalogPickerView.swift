import PhotosUI
import SwiftUI

struct ChamakCatalogPickerView: View {
    @Environment(CreditStore.self) private var credits
    @Bindable var vm: ChamakViewModel
    let wholesalerID: UUID

    @State private var photoItemSlot1: PhotosPickerItem?
    @State private var photoItemSlot2: PhotosPickerItem?
    @State private var showPickError = false

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
                title: ChamakSlot.label(for: 1, mode: vm.mode),
                subtitle: vm.mode == .setCreation ? "e.g. the necklace" : "Keeps its strengths",
                designItem: vm.selectedDesign1,
                accentColor: ChamakSlot.color(for: 1)
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
                title: ChamakSlot.label(for: 2, mode: vm.mode),
                subtitle: vm.mode == .setCreation ? "e.g. the earrings" : "Brings the upgrades",
                designItem: vm.selectedDesign2,
                accentColor: ChamakSlot.color(for: 2)
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
            HStack(spacing: 6) {
                // Same numbered disc the picked card below wears.
                ChamakSlotMark(slot: slotNumber)
                    .scaleEffect(0.85)
                Text(title)
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
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

            // 4:3 keeps the ~120pt-tall slot a phone always had, and lets it
            // grow on iPad instead of cropping the design to a strip.
            Color.clear
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay {
                    if let design = designItem {
                        // The preview is scaled-to-fill; the frame pins it to
                        // the slot so the clip below cuts at the slot's edge.
                        designPreview(design: design)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        emptySlotPlaceholder(slotNumber: slotNumber, subtitle: subtitle, accentColor: accentColor)
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
                .frame(maxHeight: 300)

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
            // Protected like every other catalogue design; this was the one
            // place a picked design rendered through plain `AsyncImage`.
            Color(hex: 0xF3F4F6)
                .overlay { ProtectedImageView(url: url) }
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
                LazyVGrid(columns: CatalogueProductCard.gridColumns, spacing: Spacing.md) {
                    ForEach(vm.catalogProducts) { product in
                        productCard(product)
                    }
                }
            }
        }
    }

    private func productCard(_ product: Product) -> some View {
        let slot: Int? = vm.selectedDesign1?.product?.id == product.id ? 1
            : vm.selectedDesign2?.product?.id == product.id ? 2
            : nil

        return ChamakDesignPickCard(
            product: product,
            slot: slot,
            slotLabel: slot.map { ChamakSlot.label(for: $0, mode: vm.mode) },
            slotColor: slot.map(ChamakSlot.color(for:)) ?? .clear
        ) {
            vm.selectProduct(product)
        }
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

// MARK: - Slots

/// One naming and colour scheme for the two inputs, shared by the slots, the
/// picker cards and (by label) the result screen and viewer — Source/Upgrade
/// for a fusion, Piece 1/Piece 2 for a set.
enum ChamakSlot {
    static func label(for slot: Int, mode: ChamakMode) -> String {
        switch (mode, slot) {
        case (.setCreation, 1): "Piece 1"
        case (.setCreation, _): "Piece 2"
        case (_, 1): "Source"
        default: "Upgrade"
        }
    }

    static func color(for slot: Int) -> Color {
        slot == 1 ? Color(hex: 0xD4AF37) : Color(hex: 0x3B82F6)
    }
}

/// The small numbered disc that marks which slot a design fills.
struct ChamakSlotMark: View {
    let slot: Int

    var body: some View {
        Text("\(slot)")
            .font(.manrope(12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(ChamakSlot.color(for: slot), in: .circle)
            .overlay { Circle().stroke(.white, lineWidth: 2) }
    }
}

// MARK: - Design Card

/// A catalogue design in the Chamak picker.
///
/// Fixed structure — square photo, one-line title, one-line details — so
/// every card in the grid is the same height whatever the product has filled
/// in. Before, the details row vanished when a product had no type or purity
/// and the grid went ragged.
private struct ChamakDesignPickCard: View {
    let product: Product
    /// 1 or 2 when this design fills a slot.
    let slot: Int?
    let slotLabel: String?
    let slotColor: Color
    let action: () -> Void

    private var isSelected: Bool { slot != nil }

    /// Same order `ChamakDesignItem.from(product:)` uses, so the card shows
    /// exactly the image that will be sent.
    private var imageURL: URL? {
        (product.processedImageURL ?? product.imageURL ?? product.rawImageURL)
            .flatMap { URL(string: $0) }
    }

    private var details: String {
        let parts = [product.jewelleryType?.capitalized, product.metalPurity?.uppercased()]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Square: scales with the column instead of the old fixed
                // 140pt strip. `UIImageView` with `clipsToBounds` can't spill
                // outside its frame, so the overflow that once swallowed a
                // neighbour's taps can't recur.
                Color(hex: 0xF3F4F6)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let imageURL {
                            ProtectedImageView(url: imageURL)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        selectionMark.padding(8)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let slotLabel {
                            Text(slotLabel)
                                .font(.manrope(11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(slotColor, in: .capsule)
                                .padding(8)
                        }
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(product.title ?? "Untitled Design")
                        .font(.manrope(13, weight: .semibold))
                        .foregroundStyle(Palette.dark)
                        .lineLimit(1)
                    Text(details)
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(isSelected ? slotColor.opacity(0.06) : Color.white)
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? slotColor : Color(hex: 0xE5E7EB), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: .black.opacity(isSelected ? 0.08 : 0.03), radius: 5, y: 2)
            // The tap target is this card's own rectangle and nothing else;
            // inferring it from the label's content is what once let a
            // neighbour's overflow claim taps.
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(product.title ?? "Untitled Design")
        .accessibilityValue(slotLabel ?? "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var selectionMark: some View {
        if let slot {
            ChamakSlotMark(slot: slot)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.dark)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.92), in: .circle)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
    }
}
