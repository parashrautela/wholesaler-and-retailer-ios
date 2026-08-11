import PhotosUI
import SwiftUI

/// The catalogue product detail modal (`_spec/05-wholesaler-screens.md` §8.3)
/// and, inside it, the "Upload/Re-upload to AI" flow (§8.4) — described there
/// as **"the only polling flow in the app"**.
///
/// Neither existed natively before this: `WholesalerCatalogueView`'s card had
/// no tap target beyond an edit/delete menu, so there was no way to view a
/// product's enhanced renders, publish it, or ever re-run the AI pipeline
/// against an existing upload. Combined with `Product.displayImageURL`
/// previously skipping two of its four source fields, a product that *had*
/// finished AI processing could still look like it never had — this sheet,
/// and the pipeline it drives, is the other half of that fix.
struct ProductDetailSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State var product: Product
    /// So the caller (the catalogue grid) can update its local copy without a
    /// full reload — mirrors `EditProductView`'s `onSaved`.
    var onUpdated: (Product) -> Void

    @State private var activeImageURL: URL?
    @State private var isPublished: Bool
    @State private var publishError: String?
    @State private var usage: UploadUsage = .unknown

    @State private var reprocess = ReprocessState()
    @State private var showReprocessConfirm = false

    init(product: Product, onUpdated: @escaping (Product) -> Void) {
        _product = State(initialValue: product)
        self.onUpdated = onUpdated
        _activeImageURL = State(initialValue: product.displayImageURL)
        _isPublished = State(initialValue: product.isPublished ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    imageArea
                    if !product.thumbnailURLs.isEmpty { thumbnailStrip }
                    header
                    specifications
                    ctaButton
                    publishRow
                }
                .padding(Spacing.screenGutter)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle(product.title ?? "Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                guard let uid = session.user?.id else { return }
                usage = await WholesalerAPI.fetchUploadUsage(wholesalerID: uid)
            }
            .sheet(isPresented: $showReprocessConfirm) {
                ReprocessConfirmSheet(hasImages: product.displayImageURL != nil) { file in
                    showReprocessConfirm = false
                    startReprocess(baseFile: file)
                }
            }
        }
        // Full-panel overlay while the pipeline runs — replaces the image the
        // way §8.4 describes, not a separate screen.
        .overlay {
            if reprocess.isActive {
                ReprocessOverlay(state: reprocess) { reprocess = ReprocessState() }
            }
        }
    }

    // MARK: - Image + thumbnails

    private var imageArea: some View {
        ZStack {
            if let url = activeImageURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "diamond")
                        .font(.system(size: 32))
                        .foregroundStyle(Palette.muted)
                    Text("No Image Found")
                        .font(.manrope(13, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 16))
        // No long-press save / drag-out — a lightweight stand-in for the
        // web's canvas-rendered `ProtectedImage`. A byte-exact port (blocking
        // the system share sheet, screenshot detection) is tracked separately
        // rather than attempted here; see the implementation plan.
        .contextMenu { }
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(product.thumbnailURLs, id: \.self) { url in
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Palette.cream)
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(url == activeImageURL ? Palette.dark.opacity(0.3) : .clear, lineWidth: 2)
                    }
                    .onTapGesture { activeImageURL = url }
                }
            }
        }
    }

    // MARK: - Header + specs

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(product.title ?? "Untitled Product")
                .font(.cirka(22))
                .foregroundStyle(Palette.foreground)

            Text("\((product.category ?? "Jewellery").capitalized) • \(sku)")
                .font(.manrope(13))
                .foregroundStyle(Palette.muted)

            HStack(spacing: 8) {
                Circle()
                    .fill(product.stockAvailable == true ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(product.stockAvailable == true ? "In stock" : "Out of stock")
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(product.stockAvailable == true ? .green : .red)
                Text("|").foregroundStyle(Palette.muted)
                Text(weightLabel(product.netWeight, fallback: "20g"))
                    .font(.manrope(12, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    /// `product.sku || "JWL-" + last 6 chars of id, uppercased`.
    private var sku: String {
        String(product.id.suffix(6)).uppercased().isEmpty
            ? "JWL-000000"
            : "JWL-\(product.id.suffix(6).uppercased())"
    }

    private var specifications: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Specifications")
                .font(.manrope(14, weight: .bold))
                .foregroundStyle(Palette.foreground)

            specRow("Purity", product.metalPurity?.uppercased() ?? "24K")
            specRow("Gross weight", weightLabel(product.grossWeight))
            specRow("Stone weight", weightLabel(product.stoneWeight))
            specRow("Net weight", weightLabel(product.netWeight))
        }
        .padding(Spacing.md)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 12))
    }

    private func specRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.manrope(13)).foregroundStyle(Palette.muted)
            Spacer()
            Text(value).font(.manrope(13, weight: .semibold)).foregroundStyle(Palette.foreground)
        }
    }

    private func weightLabel(_ value: Double?, fallback: String = "-") -> String {
        guard let value else { return fallback }
        return String(format: "%.2fg", value)
    }

    // MARK: - CTA + publish

    private var isLimitReached: Bool {
        guard let limit = usage.limit else { return false }
        return usage.used >= limit
    }

    private var ctaTitle: String {
        if isLimitReached { return "Daily upload limit reached" }
        return product.displayImageURL == nil ? "Upload Image to AI" : "Re-upload to AI"
    }

    private var ctaButton: some View {
        Button {
            showReprocessConfirm = true
        } label: {
            Text(ctaTitle)
                .font(.manrope(14, weight: .bold))
                .foregroundStyle(isLimitReached ? Palette.muted : Palette.dark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isLimitReached ? Palette.border : Palette.dark, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isLimitReached)
    }

    private var publishRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Publish to Retailer")
                    .font(.manrope(15, weight: .semibold))
                    .foregroundStyle(Palette.foreground)
                Spacer()
                Toggle("", isOn: $isPublished)
                    .labelsHidden()
                    .tint(Color(hex: 0x34C759))
                    .onChange(of: isPublished) { _, newValue in
                        Task { await togglePublish(newValue) }
                    }
            }
            if let publishError {
                Text(publishError)
                    .font(.manrope(12))
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, Spacing.sm)
    }

    private func togglePublish(_ newValue: Bool) async {
        publishError = nil
        do {
            try await WholesalerAPI.updateProductFlags(id: product.id, isPublished: newValue)
            onUpdated(withPublished(newValue))
        } catch {
            // Optimistic toggle, reverts silently on the web too.
            isPublished.toggle()
            publishError = "Couldn't update — please try again."
        }
    }

    private func withPublished(_ published: Bool) -> Product {
        Product(
            id: product.id, wholesalerId: product.wholesalerId, wholesalerEmail: product.wholesalerEmail,
            title: product.title, jewelleryType: product.jewelleryType, category: product.category,
            style: product.style, size: product.size, stockAvailable: product.stockAvailable,
            makeToOrderDays: product.makeToOrderDays, metalPurity: product.metalPurity,
            netWeight: product.netWeight, grossWeight: product.grossWeight, stoneWeight: product.stoneWeight,
            rawImageURL: product.rawImageURL, processedImageURL: product.processedImageURL,
            imageURL: product.imageURL, generatedImageURLs: product.generatedImageURLs,
            isPublished: published, createdAt: product.createdAt
        )
    }

    // MARK: - Re-upload to AI

    private func startReprocess(baseFile: PickedFile?) {
        guard let uid = session.user?.id else { return }
        reprocess = ReprocessState(status: "Initiating re-upload...")

        Task {
            do {
                reprocess.status = "Clearing old images..."
                try await WholesalerAPI.clearProductImages(id: product.id, wholesalerID: uid)

                reprocess.status = "Queueing AI pipeline..."
                try await WholesalerAPI.reprocessProduct(
                    productID: product.id, wholesalerID: uid, file: baseFile
                )

                reprocess.status = "AI processing in progress..."
                let urls = try await poll()

                let updated = withGeneratedImages(urls)
                product = updated
                activeImageURL = updated.displayImageURL
                onUpdated(updated)
                usage = await WholesalerAPI.fetchUploadUsage(wholesalerID: uid)

                reprocess.status = "Processing complete!"
                try? await Task.sleep(for: .milliseconds(1500))
                reprocess = ReprocessState()
            } catch {
                reprocess.failure = (error as? WholesalerAPI.PipelineError)?.message
                    ?? error.localizedDescription
            }
        }
    }

    /// §8.4 step 4 — 5 s cadence, 5 min deadline, driven from the view so a
    /// dismissed sheet can simply stop awaiting rather than needing its own
    /// cancellation plumbing inside the API layer.
    private func poll() async throws -> [String] {
        let deadline = ContinuousClock.now + WholesalerAPI.pollTimeout
        var backgroundRemoved = false

        while ContinuousClock.now < deadline {
            switch await WholesalerAPI.reprocessPollTick(
                productID: product.id, backgroundRemovedAlready: backgroundRemoved
            ) {
            case .done(let urls):
                return urls
            case .pending(let removed):
                if removed, !backgroundRemoved {
                    backgroundRemoved = true
                    reprocess.status = "Background removed, enhancing..."
                }
            }
            try await Task.sleep(for: WholesalerAPI.pollInterval)
        }
        throw WholesalerAPI.PipelineError(message: "Timed out waiting for processed images (5 min). Please retry.")
    }

    private func withGeneratedImages(_ urls: [String]) -> Product {
        Product(
            id: product.id, wholesalerId: product.wholesalerId, wholesalerEmail: product.wholesalerEmail,
            title: product.title, jewelleryType: product.jewelleryType, category: product.category,
            style: product.style, size: product.size, stockAvailable: product.stockAvailable,
            makeToOrderDays: product.makeToOrderDays, metalPurity: product.metalPurity,
            netWeight: product.netWeight, grossWeight: product.grossWeight, stoneWeight: product.stoneWeight,
            rawImageURL: product.rawImageURL, processedImageURL: urls.first,
            imageURL: product.imageURL, generatedImageURLs: urls,
            isPublished: product.isPublished, createdAt: product.createdAt
        )
    }
}

// MARK: - Re-upload state machine

@Observable
final class ReprocessState {
    var status: String?
    var failure: String?

    init(status: String? = nil) { self.status = status }

    var isActive: Bool { status != nil || failure != nil }
}

/// The full-panel overlay shown while `ReprocessState` is active — status text
/// while running, or the failure state with a dismiss button.
private struct ReprocessOverlay: View {
    let state: ReprocessState
    let onDismissFailure: () -> Void

    var body: some View {
        ZStack {
            Color.white.opacity(0.97).ignoresSafeArea()

            if let failure = state.failure {
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.red.opacity(0.12)).frame(width: 48, height: 48)
                        Image(systemName: "exclamationmark").font(.system(size: 20, weight: .bold)).foregroundStyle(.red)
                    }
                    Text("Reprocessing Failed")
                        .font(.manrope(16, weight: .bold))
                        .foregroundStyle(.red)
                    Text(failure)
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                    Button("Close") { onDismissFailure() }
                        .buttonStyle(.plain)
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(Palette.dark, in: Capsule())
                        .padding(.top, 8)
                }
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(state.status ?? "")
                        .font(.manrope(15, weight: .bold))
                        .foregroundStyle(Palette.foreground)
                    Text("This may take up to a minute")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }
}

// MARK: - Confirmation sheet (§8.4, before the panel above appears)

private struct ReprocessConfirmSheet: View {
    let hasImages: Bool
    let onConfirm: (PickedFile?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var newFile: PickedFile?
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(Color.orange.opacity(0.15)).frame(width: 48, height: 48)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hasImages ? "Re-upload to AI?" : "Upload Image to AI")
                            .font(.manrope(16, weight: .bold))
                        Text(hasImages
                            ? "This will clear the current processed results. You can optionally replace the base image below."
                            : "Select a base photo below to start the AI processing pipeline for this product.")
                            .font(.manrope(13))
                            .foregroundStyle(Palette.muted)
                    }
                }

                Text("Base Photo Selection")
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(Palette.muted)

                Button {
                    showPicker = true
                } label: {
                    VStack(spacing: 8) {
                        if let newFile, let image = newFile.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text("New Base Photo")
                                .font(.manrope(10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Palette.dark, in: Capsule())
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 28))
                                .foregroundStyle(Palette.muted)
                            Text("Drag new image here, or browse")
                                .font(.manrope(12, weight: .semibold))
                                .foregroundStyle(Palette.foreground)
                            Text(hasImages
                                ? "JPEG, PNG, or WebP. Leave blank to keep current photo."
                                : "JPEG, PNG, or WebP is required.")
                                .font(.manrope(11))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(Color(white: 0.98), in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                            .foregroundStyle(Palette.border)
                    }
                }
                .buttonStyle(.plain)
                .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let jpeg = ImageNormalizer.jpeg(from: data, maxDimension: ImageNormalizer.maxProductDimension) {
                            newFile = PickedFile(data: jpeg, filename: "reupload.jpg", mimeType: "image/jpeg")
                        }
                        photoItem = nil
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.manrope(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1) }

                    Button(hasImages && newFile == nil ? "Re-upload" : "Upload & Process") {
                        onConfirm(newFile)
                    }
                    .buttonStyle(.plain)
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.dark, in: RoundedRectangle(cornerRadius: 10))
                    .disabled(!hasImages && newFile == nil)
                    .opacity(!hasImages && newFile == nil ? 0.5 : 1)
                }
            }
            .padding(Spacing.xl)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
