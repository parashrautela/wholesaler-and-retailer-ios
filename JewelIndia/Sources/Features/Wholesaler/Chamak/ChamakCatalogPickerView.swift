import PhotosUI
import SwiftUI

struct ChamakCatalogPickerView: View {
    @Environment(CreditStore.self) private var credits
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: ChamakViewModel
    let wholesalerID: UUID

    @State private var photoItemSlot1: PhotosPickerItem?
    @State private var photoItemSlot2: PhotosPickerItem?
    @State private var photoItemSlot3: PhotosPickerItem?
    @State private var photoItemSlot4: PhotosPickerItem?
    @State private var showPickError = false
    @State private var selectedCategory = "All"
    @State private var previewImageURL: URL?

    // Direct photo upload pending state for Set Creation
    @State private var pendingUpload: (slot: Int, data: Data)?
    @State private var showTypePickerSheet = false

    private var categories: [String] {
        let values = vm.catalogProducts.compactMap { product in
            (product.jewelleryType ?? product.category)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return ["All"] + Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var visibleProducts: [Product] {
        guard selectedCategory != "All" else { return vm.catalogProducts }
        return vm.catalogProducts.filter {
            ($0.jewelleryType ?? $0.category)?.caseInsensitiveCompare(selectedCategory) == .orderedSame
        }
    }

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    subHeaderBar

                    if let err = vm.errorMessage {
                        inlineErrorBanner(err)
                    }

                    selectionSlotsSection
                    catalogGridSection
                }
                .padding(.horizontal, Spacing.base)
                .padding(.top, Spacing.sm)
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
        .sheet(isPresented: $showTypePickerSheet, onDismiss: {
            pendingUpload = nil
        }) {
            if let pending = pendingUpload {
                declaredTypePickerSheet(slot: pending.slot, data: pending.data)
                    .presentationDetents([.medium])
            }
        }
        .fullScreenCover(item: Binding(
            get: { previewImageURL.map { PreviewURLItem(url: $0) } },
            set: { previewImageURL = $0?.url }
        )) { item in
            ChamakImageViewer(images: [
                ChamakViewerImage(id: "preview", label: "Catalogue Preview", url: item.url, isResult: false)
            ], startIndex: 0)
        }
        .onChange(of: photoItemSlot1) { _, item in load(item, slot: 1) }
        .onChange(of: photoItemSlot2) { _, item in load(item, slot: 2) }
        .onChange(of: photoItemSlot3) { _, item in load(item, slot: 3) }
        .onChange(of: photoItemSlot4) { _, item in load(item, slot: 4) }
        .alert("Photo Couldn't Be Loaded", isPresented: $showPickError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("That photo couldn't be loaded — please try a different image.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.dark)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Text("Chamak Studio")
                .font(.cirka(isRegularWidth ? 30 : 25, weight: .bold))
                .foregroundStyle(Palette.dark)

            Spacer()

            creditPill
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

    private var creditPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0xB4833E))

            if let available = credits.wallet?.available {
                Text("\(available) credits")
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(Color(hex: 0xB4833E))
            } else {
                Text("Credits")
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(Color(hex: 0xB4833E))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color(hex: 0xFDF8EE), in: Capsule())
        .overlay {
            Capsule().stroke(Color(hex: 0xF6E8CD), lineWidth: 1)
        }
    }

    // MARK: - SubHeader Bar

    private var subHeaderBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(vm.mode == .setCreation ? "Stage your set (2–4 pieces)." : "Blend two designs.")
                .font(.manrope(17, weight: .bold))
                .foregroundStyle(Color(hex: 0x374151))

            Spacer()

            Button {
                vm.step = .gallery
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 13))
                    Text("Design Archive")
                        .font(.manrope(12, weight: .semibold))
                }
                .foregroundStyle(Color(hex: 0x5E5D5A))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    // MARK: - Inline Error Banner

    private func inlineErrorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0xD97706))

            Text(error)
                .font(.manrope(13, weight: .medium))
                .foregroundStyle(Color(hex: 0x92400E))
                .lineLimit(2)

            Spacer()

            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x92400E))
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: 0xFEF3C7), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xFDE68A), lineWidth: 1)
        }
    }

    // MARK: - Selection Slots Section

    private var selectionSlotsSection: some View {
        Group {
            if vm.mode == .setCreation {
                VStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.md) {
                        slotCard(
                            slotNumber: 1,
                            emptyTitle: "Piece 1",
                            subtitle: "Required",
                            designItem: vm.selectedDesign1,
                            accentColor: ChamakSlot.color(for: 1),
                            photoBinding: $photoItemSlot1
                        )

                        slotCard(
                            slotNumber: 2,
                            emptyTitle: "Piece 2",
                            subtitle: "Required",
                            designItem: vm.selectedDesign2,
                            accentColor: ChamakSlot.color(for: 2),
                            photoBinding: $photoItemSlot2
                        )
                    }

                    HStack(spacing: Spacing.md) {
                        slotCard(
                            slotNumber: 3,
                            emptyTitle: "Piece 3",
                            subtitle: "Optional",
                            designItem: vm.selectedDesign3,
                            accentColor: ChamakSlot.color(for: 3),
                            photoBinding: $photoItemSlot3
                        )

                        slotCard(
                            slotNumber: 4,
                            emptyTitle: "Piece 4",
                            subtitle: "Optional",
                            designItem: vm.selectedDesign4,
                            accentColor: ChamakSlot.color(for: 4),
                            photoBinding: $photoItemSlot4
                        )
                    }
                }
            } else {
                HStack(spacing: Spacing.md) {
                    slotCard(
                        slotNumber: 1,
                        emptyTitle: "Core design",
                        subtitle: "Keeps its Identity",
                        designItem: vm.selectedDesign1,
                        accentColor: Color(hex: 0xD97706),
                        photoBinding: $photoItemSlot1
                    )

                    slotCard(
                        slotNumber: 2,
                        emptyTitle: "New Direction",
                        subtitle: "New Expression",
                        designItem: vm.selectedDesign2,
                        accentColor: Color(hex: 0x3B82F6),
                        photoBinding: $photoItemSlot2
                    )
                }
            }
        }
        .frame(maxWidth: isRegularWidth ? 760 : .infinity)
        .frame(maxWidth: .infinity)
    }

    private func slotCard(
        slotNumber: Int,
        emptyTitle: String,
        subtitle: String,
        designItem: ChamakDesignItem?,
        accentColor: Color,
        photoBinding: Binding<PhotosPickerItem?>
    ) -> some View {
        let isFilled = designItem != nil

        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let design = designItem {
                    designPreview(design: design)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    // Top leading clear button
                    Button {
                        vm.clearSlot(slotNumber)
                    } label: {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                    }
                    .padding(10)
                } else {
                    VStack(alignment: .center, spacing: 0) {
                        HStack {
                            PhotosPicker(selection: photoBinding, matching: .images) {
                                Circle()
                                    .fill(accentColor)
                                    .frame(width: 26, height: 26)
                                    .overlay {
                                        Image(systemName: "plus")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                        .padding(.top, 12)
                        .padding(.leading, 12)

                        Spacer()

                        VStack(spacing: 4) {
                            Text(emptyTitle)
                                .font(.manrope(14, weight: .bold))
                                .foregroundStyle(Color(hex: 0x374151))

                            Text(subtitle)
                                .font(.manrope(11, weight: .medium))
                                .foregroundStyle(Color(hex: 0x9CA3AF))
                        }
                        .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity, minHeight: vm.mode == .setCreation ? 140 : 185)
                    .contentShape(Rectangle())
                }
            }

            if let design = designItem {
                VStack(alignment: .leading, spacing: 3) {
                    Text(design.title)
                        .font(.manrope(12, weight: .bold))
                        .foregroundStyle(Palette.dark)
                        .lineLimit(1)

                    if vm.mode == .setCreation {
                        HStack(spacing: 4) {
                            Text(design.displayTypeLabel)
                                .font(.manrope(10, weight: .bold))
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentColor.opacity(0.12), in: Capsule())
                            Spacer()
                        }
                    } else {
                        Text(slotNumber == 1 ? "Keeps its identity" : "New expression")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xF9F9F8))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            if isFilled {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(accentColor, lineWidth: 1.5)
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        Color(hex: 0xE5E7EB),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            }
        }
    }

    @ViewBuilder
    private func designPreview(design: ChamakDesignItem) -> some View {
        if let localData = design.localImageData, let uiImage = UIImage(data: localData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let url = design.displayURL(.card) {
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

    // MARK: - Catalog Grid Section

    private var catalogGridSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pick from Catalogue")
                    .font(.cirka(19, weight: .bold))
                    .foregroundStyle(Palette.dark)
                Spacer()
                if !vm.catalogProducts.isEmpty {
                    Text("\(vm.catalogProducts.count) items")
                        .font(.manrope(12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }
            }

            categoryFilterBar

            if vm.isLoadingProducts {
                ProgressView()
                    .tint(Palette.dark)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if vm.catalogProducts.isEmpty {
                emptyCataloguePlaceholder
            } else {
                LazyVGrid(
                    columns: isRegularWidth
                        ? [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: Spacing.md)]
                        : [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)],
                    spacing: Spacing.md
                ) {
                    ForEach(visibleProducts) { product in
                        catalogProductCard(product)
                    }
                }
            }
        }
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    let isSelected = selectedCategory == category
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category)
                            .font(.manrope(12, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? .white : Palette.dark)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color(hex: 0x111827) : Color.white, in: Capsule())
                            .overlay {
                                Capsule().stroke(Color(hex: 0xE5E7EB), lineWidth: isSelected ? 0 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func catalogProductCard(_ product: Product) -> some View {
        let slot: Int? = vm.slot(of: product).flatMap { $0 <= vm.slotCount ? $0 : nil }
        let isSelected = slot != nil
        let blockReason = vm.selectionBlockReason(for: product)
        let isBlocked = blockReason != nil && !isSelected

        let imageURL = (product.processedImageURL ?? product.imageURL ?? product.rawImageURL)
            .flatMap { URL(string: $0) }

        return Button {
            vm.selectProduct(product)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
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

                    // Blocked overlay when item cannot be selected
                    if isBlocked {
                        Color.black.opacity(0.38)
                            .overlay {
                                VStack(spacing: 2) {
                                    Image(systemName: "slash.circle")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)

                                    if case .sameTypeSelected(let typeLabel) = blockReason {
                                        Text("\(typeLabel) in set")
                                            .font(.manrope(10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 4)
                                    } else if case .setFull = blockReason {
                                        Text("Set full (4/4)")
                                            .font(.manrope(10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                    }
                                }
                            }
                    }

                    // Expand / Zoom button
                    if let imageURL, !isBlocked {
                        Button {
                            previewImageURL = imageURL
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

                    // Slot Badge if selected
                    if let slot {
                        VStack {
                            Spacer()
                            HStack {
                                Text(ChamakSlot.label(for: slot, mode: vm.mode))
                                    .font(.manrope(11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(ChamakSlot.color(for: slot), in: Capsule())
                                    .padding(8)
                                Spacer()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.title ?? "Catalogue Design")
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(isBlocked ? Palette.muted : Palette.dark)
                        .lineLimit(1)

                    Text(product.jewelleryType?.capitalized ?? "Jewellery")
                        .font(.manrope(11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(isBlocked ? 0.6 : 1.0)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? ChamakSlot.color(for: slot ?? 1) : Color(hex: 0xE5E7EB),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var emptyCataloguePlaceholder: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(Color(hex: 0xCA8A04))
            Text("No catalogue items found")
                .font(.manrope(14, weight: .semibold))
                .foregroundStyle(Palette.dark)
            Text("Upload photos directly using the + buttons in the slots above.")
                .font(.manrope(12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    // MARK: - Direct Upload Jewellery Type Picker Sheet

    private func declaredTypePickerSheet(slot: Int, data: Data) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Select the jewellery type for this piece. Each item in your set must be a distinct type.")
                    .font(.manrope(13, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, Spacing.base)
                    .padding(.top, Spacing.sm)

                List {
                    ForEach(JewelleryTypeCanonical.allCanonical, id: \.self) { canonicalKey in
                        let label = JewelleryTypeCanonical.displayLabel(for: canonicalKey)
                        let alreadyUsed = vm.setPieces.contains { $0.canonicalJewelleryType == canonicalKey }

                        Button {
                            guard !alreadyUsed else { return }
                            vm.setCustomImage(data: data, forSlot: slot, declaredJewelleryType: canonicalKey)
                            pendingUpload = nil
                            showTypePickerSheet = false
                        } label: {
                            HStack {
                                Text(label)
                                    .font(.manrope(15, weight: alreadyUsed ? .regular : .semibold))
                                    .foregroundStyle(alreadyUsed ? Palette.muted : Palette.dark)

                                Spacer()

                                if alreadyUsed {
                                    Text("Already in set")
                                        .font(.manrope(12, weight: .medium))
                                        .foregroundStyle(Color(hex: 0x9CA3AF))
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Palette.muted)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(alreadyUsed)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Piece \(slot) Jewellery Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pendingUpload = nil
                        showTypePickerSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)

            Button {
                Task {
                    await vm.startVisionAnalysis(wholesalerID: wholesalerID)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Text(vm.mode == .setCreation ? "Choose Backdrop" : "Start Analyze")
                        .font(.manrope(16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    vm.canStartAnalysis
                        ? LinearGradient(colors: [Color(hex: 0x4F4F4F), Color(hex: 0x232323)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color(hex: 0x9CA3AF), Color(hex: 0x6B7280)], startPoint: .top, endPoint: .bottom),
                    in: Capsule()
                )
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.22), radius: 8, y: 4)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!vm.canStartAnalysis || vm.isSubmitting)
            .frame(maxWidth: isRegularWidth ? 640 : .infinity)
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.md)
        }
        .background(Color.white.opacity(0.96))
    }

    private func load(_ item: PhotosPickerItem?, slot: Int) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = ImageNormalizer.jpeg(from: data, maxDimension: ImageNormalizer.maxProductDimension) else {
                showPickError = true
                clearBinding(for: slot)
                return
            }
            clearBinding(for: slot)
            if vm.mode == .setCreation {
                pendingUpload = (slot: slot, data: jpeg)
                showTypePickerSheet = true
            } else {
                vm.setCustomImage(data: jpeg, forSlot: slot)
            }
        }
    }

    private func clearBinding(for slot: Int) {
        switch slot {
        case 1: photoItemSlot1 = nil
        case 2: photoItemSlot2 = nil
        case 3: photoItemSlot3 = nil
        default: photoItemSlot4 = nil
        }
    }
}

private struct PreviewURLItem: Identifiable {
    let id = UUID()
    let url: URL
}
