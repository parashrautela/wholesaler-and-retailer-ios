import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class ChamakViewModel {

    enum Step: Equatable {
        case catalogPicker
        case analyzing
        case sliderForm
        case setStyling
        case generating
        case result
        case failed
        case gallery
    }

    var step: Step = .catalogPicker

    /// Which of the two Chamak operations this flow instance is running.
    /// Set once by whoever presents `ChamakFlowCoordinator` and left alone
    /// afterwards — `resetToPicker()` deliberately does not reset it, so
    /// "New Set"/"New Combine" stays in the mode the wholesaler opened.
    var mode: ChamakMode = .fusion

    // Data
    var catalogProducts: [Product] = []
    /// Where the picker's designs come from. Everything after the picker —
    /// analysis, generation, credits, gallery — is keyed on the signed-in
    /// user and is the same for both.
    var catalogueSource: ChamakCatalogueSource = .ownProducts
    var galleryGenerations: [ChamakGeneration] = []
    /// Signed thumbnails for `galleryGenerations`, keyed by generation id.
    /// Outputs live in a private bucket, so a tile has nothing to show until
    /// its path has been signed.
    var galleryThumbnailURLs: [UUID: URL] = [:]
    var selectedDesign1: ChamakDesignItem?
    var selectedDesign2: ChamakDesignItem?
    /// Set Creation only: the optional third and fourth pieces.
    var selectedDesign3: ChamakDesignItem?
    var selectedDesign4: ChamakDesignItem?

    /// The pieces that go into a set, in order. Fusion always uses two.
    var setPieces: [ChamakDesignItem] {
        let all = [selectedDesign1, selectedDesign2] + (mode == .setCreation ? [selectedDesign3, selectedDesign4] : [])
        return all.compactMap { $0 }
    }

    /// The rate-card key for this set's size (2 = the base price).
    var setPriceKey: String {
        let count = max(2, setPieces.count)
        return count == 2 ? "chamak.set_creation" : "chamak.set_creation_\(count)"
    }
    var currentGeneration: ChamakGeneration?
    var signedOutputImageURL: URL?
    /// The 2048px copy, signed only so the full-screen viewer can zoom into
    /// it. Nil until `signOutputs` resolves, and until then the viewer uses
    /// the screen-sized one.
    var signedFullOutputImageURL: URL?
    var signedOutputImageURLs: [URL] = []

    // Form inputs
    var sliderValues: [String: Double] = [:]
    var noteText: String = ""
    var selectedBackdrop: SetBackdrop = .velvetBust
    var selectedStylingChips: Set<SetStylingChip> = []

    var composedSetNote: String? {
        let chipNotes = SetStylingChip.all
            .filter { selectedStylingChips.contains($0) }
            .map(\.instruction)
        let manual = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = chipNotes + (manual.isEmpty ? [] : [manual])
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    func toggleStylingChip(_ chip: SetStylingChip) {
        if selectedStylingChips.contains(chip) {
            selectedStylingChips.remove(chip)
        } else {
            selectedStylingChips.insert(chip)
        }
    }

    // Idempotency & Credits (Rules §2.3, §2.4, Task i7)
    private var pendingGenerateKey: String?
    var insufficientCreditsError: ChamakAPI.InsufficientCreditsError?
    var showInsufficientCreditsSheet: Bool = false
    var toastMessage: String?
    var showToast: Bool = false

    /// Non-nil when the last gallery fetch threw. Distinct from `errorMessage`,
    /// which belongs to the generation flow: without this the gallery cannot
    /// tell an empty account from a failed read, and shows the same "no
    /// generations yet" copy for both — which is how a fetch failure spent so
    /// long looking like an empty table.
    var galleryErrorMessage: String?
    var isRefreshingGallery: Bool = false

    // Loading & UI States
    var isLoadingProducts: Bool = false
    var isSubmitting: Bool = false
    var errorMessage: String?

    // Quotes
    var activeQuoteIndex: Int = 0
    private var quoteTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    // Feedback
    var isShowingFeedbackSheet: Bool = false
    var feedbackSatisfied: Bool = true
    var feedbackText: String = ""
    var feedbackSubmitted: Bool = false

    // MARK: - Initial Load

    func load(wholesalerID: UUID) async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        async let productsTask = Self.fetchProducts(from: catalogueSource, wholesalerID: wholesalerID)
        async let galleryTask = ChamakAPI.fetchWholesalerGallery(wholesalerID: wholesalerID)

        do {
            catalogProducts = try await productsTask
        } catch {
            catalogProducts = []
        }

        do {
            galleryGenerations = try await galleryTask
            galleryErrorMessage = nil
            await signGalleryThumbnails()
        } catch {
            galleryGenerations = []
            galleryErrorMessage = Self.galleryFailureCopy(error)
        }
    }

    private nonisolated static func fetchProducts(
        from source: ChamakCatalogueSource,
        wholesalerID: UUID
    ) async throws -> [Product] {
        switch source {
        case .ownProducts:
            return try await ChamakAPI.fetchWholesalerProducts(wholesalerID: wholesalerID)
        case .storeDesigns:
            return try await ChamakAPI.fetchStoreProducts()
        }
    }

    /// Re-reads the gallery without touching the catalogue or any flow state.
    /// `load` only runs from `ChamakFlowCoordinator`'s `.task`, i.e. once per
    /// presentation, so without this a generation finished in this session is
    /// missing from the gallery until the whole flow is dismissed and reopened.
    func refreshGallery(wholesalerID: UUID) async {
        isRefreshingGallery = true
        defer { isRefreshingGallery = false }
        do {
            galleryGenerations = try await ChamakAPI.fetchWholesalerGallery(wholesalerID: wholesalerID)
            galleryErrorMessage = nil
            await signGalleryThumbnails()
        } catch {
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            galleryErrorMessage = Self.galleryFailureCopy(error)
        }
    }

    private func signGalleryThumbnails() async {
        // Tiles show the card-sized copy: ~41 KB each rather than the
        // multi-megabyte output. Older rows have no copy and sign the original.
        let paths = galleryGenerations.compactMap { $0.outputPath(.card) }
        let signed = await ChamakAPI.getSignedURLs(paths: paths)
        var byID: [UUID: URL] = [:]
        for gen in galleryGenerations {
            if let path = gen.outputPath(.card), let url = signed[path] {
                byID[gen.id] = url
            }
        }
        galleryThumbnailURLs = byID
    }

    /// Sign the output at the two sizes the result screen needs: the
    /// screen-sized copy it shows, and the full-size one behind pinch-to-zoom.
    /// Signing is not downloading — the big one only travels if it's opened.
    private func signOutputs(for generation: ChamakGeneration) async {
        let outputPaths = generation.outputImages.compactMap { $0.variants[ImageSize.detail.rawValue] ?? $0.path }
        signedOutputImageURLs = await withTaskGroup(of: URL?.self, returning: [URL].self) { group in
            for path in outputPaths { group.addTask { await ChamakAPI.getSignedURL(path: path) } }
            var urls: [URL] = []
            for await url in group { if let url { urls.append(url) } }
            return urls
        }
        guard let detail = generation.outputPath(.detail) else { return }
        signedOutputImageURL = await ChamakAPI.getSignedURL(path: detail)

        guard let full = generation.outputPath(.full), full != detail else {
            signedFullOutputImageURL = signedOutputImageURL
            return
        }
        signedFullOutputImageURL = await ChamakAPI.getSignedURL(path: full)
    }

    /// Release builds get copy a wholesaler can act on; DEBUG builds also get
    /// the underlying error, because the useful detail here (which key failed
    /// to decode, which row) is exactly what a friendly message throws away.
    private static func galleryFailureCopy(_ error: Error) -> String {
        let base = "Couldn't load your gallery. Check your connection and try again."
        #if DEBUG
        return "\(base)\n\n[debug] \(error)"
        #else
        return base
        #endif
    }

    // MARK: - Selection

    enum SelectionBlockReason: Equatable, Sendable {
        case missingImage
        case missingType
        case sameTypeSelected(String)
        case setFull

        var message: String {
            switch self {
            case .missingImage:
                return "This product has no usable image."
            case .missingType:
                return "Add a jewellery type to use this item in a set."
            case .sameTypeSelected(let label):
                return "A \(label.lowercased()) is already selected. Remove it to choose another."
            case .setFull:
                return "Remove a piece to add another."
            }
        }
    }

    /// Evaluates if a catalogue product can be added to the current set or why it is blocked.
    func selectionBlockReason(for product: Product) -> SelectionBlockReason? {
        guard mode == .setCreation else { return nil }
        // 1. If product is already selected, it can always be deselected!
        if slot(of: product) != nil {
            return nil
        }
        // 2. Check image availability
        let url = product.processedImageURL ?? product.imageURL ?? product.rawImageURL ?? ""
        if url.isEmpty {
            return .missingImage
        }
        // 3. Check canonical jewellery type (never fall back to material category!)
        guard let cType = JewelleryTypeCanonical.canonicalize(product.jewelleryType) else {
            return .missingType
        }
        // 4. Block duplicate canonical types within the set
        if let existing = setPieces.first(where: { $0.canonicalJewelleryType == cType }) {
            let label = JewelleryTypeCanonical.displayLabel(for: cType)
            return .sameTypeSelected(label)
        }
        // 5. Block addition if set is full (4 items)
        if setPieces.count >= slotCount {
            return .setFull
        }
        return nil
    }

    /// Which slot a catalogue design sits in, if any.
    func slot(of product: Product) -> Int? {
        [selectedDesign1, selectedDesign2, selectedDesign3, selectedDesign4]
            .firstIndex { $0?.product?.id == product.id }
            .map { $0 + 1 }
    }

    func design(inSlot slot: Int) -> ChamakDesignItem? {
        switch slot {
        case 1: selectedDesign1
        case 2: selectedDesign2
        case 3: selectedDesign3
        default: selectedDesign4
        }
    }

    func clearSlot(_ slot: Int) {
        switch slot {
        case 1: selectedDesign1 = nil
        case 2: selectedDesign2 = nil
        case 3: selectedDesign3 = nil
        default: selectedDesign4 = nil
        }
        if mode == .setCreation {
            compactSlots()
        }
    }

    /// Keep set slots contiguous (1...N) so removal renumbers consistently.
    private func compactSlots() {
        guard mode == .setCreation else { return }
        let active = setPieces
        selectedDesign1 = active.indices.contains(0) ? active[0] : nil
        selectedDesign2 = active.indices.contains(1) ? active[1] : nil
        selectedDesign3 = active.indices.contains(2) ? active[2] : nil
        selectedDesign4 = active.indices.contains(3) ? active[3] : nil
    }

    /// How many slots this mode offers: two for Fusion, four for a set.
    var slotCount: Int { mode == .setCreation ? 4 : 2 }

    func selectProduct(_ product: Product) {
        if let slot = slot(of: product), slot <= slotCount {
            clearSlot(slot)
            return
        }

        if mode == .setCreation {
            if let reason = selectionBlockReason(for: product) {
                errorMessage = reason.message
                return
            }
            let target = (1...slotCount).first { design(inSlot: $0) == nil }
            guard let target else {
                errorMessage = "Remove a piece to add another."
                return
            }
            place(.from(product: product), inSlot: target)
            compactSlots()
            errorMessage = nil
        } else {
            // Fusion mode: silently replace the last slot when full
            let target = (1...slotCount).first { design(inSlot: $0) == nil } ?? slotCount
            place(.from(product: product), inSlot: target)
        }
    }

    func setCustomImage(data: Data, forSlot slot: Int, declaredJewelleryType: String? = nil) {
        if mode == .setCreation {
            if let type = declaredJewelleryType, let cType = JewelleryTypeCanonical.canonicalize(type) {
                if setPieces.contains(where: { $0.canonicalJewelleryType == cType }) {
                    let label = JewelleryTypeCanonical.displayLabel(for: cType)
                    errorMessage = "A \(label.lowercased()) is already in your set. Remove it to choose another."
                    return
                }
            }
        }
        place(.from(imageData: data, slot: slot, declaredJewelleryType: declaredJewelleryType), inSlot: slot)
        if mode == .setCreation {
            compactSlots()
        }
    }

    private func place(_ item: ChamakDesignItem, inSlot slot: Int) {
        switch slot {
        case 1: selectedDesign1 = item
        case 2: selectedDesign2 = item
        case 3: selectedDesign3 = item
        default: selectedDesign4 = item
        }
    }

    var canStartAnalysis: Bool {
        if mode == .setCreation {
            let pieces = setPieces
            guard pieces.count >= 2, pieces.count <= 4 else { return false }
            guard pieces.allSatisfy(\.hasImage) else { return false }
            guard Set(pieces.map(\.id)).count == pieces.count else { return false }
            let hashes = pieces.compactMap(\.contentHash)
            guard Set(hashes).count == hashes.count else { return false }
            // Every piece must have a canonical jewellery type and all must be distinct
            let types = pieces.compactMap(\.canonicalJewelleryType)
            guard types.count == pieces.count else { return false }
            return Set(types).count == pieces.count
        } else {
            guard selectedDesign1 != nil, selectedDesign2 != nil else { return false }
            let pieces = setPieces
            guard pieces.allSatisfy(\.hasImage) else { return false }
            guard Set(pieces.map(\.id)).count == pieces.count else { return false }
            let hashes = pieces.compactMap(\.contentHash)
            return Set(hashes).count == hashes.count
        }
    }

    // MARK: - Stage 1 Vision Analysis (Fusion) / Row Creation (Set Creation)

    /// Named for its original, Fusion-only purpose but now the shared entry
    /// point for both modes: it always uploads/resolves the two source
    /// images and creates the `chamak_generations` row. What happens next
    /// diverges — Set Creation has no analysis stage at all (confirmed
    /// against `ai-pipeline/app/main.py`: "skips stage 1 entirely — there is
    /// nothing to analyse when both pieces are reproduced as-is"), so it
    /// goes straight to the backdrop-styling step instead of triggering
    /// `/api/chamak/analyze` and polling for `.awaitingInput`.
    func startVisionAnalysis(wholesalerID: UUID) async {
        guard let d1 = selectedDesign1, let d2 = selectedDesign2 else { return }

        step = .analyzing
        startQuoteRotation()

        do {
            // Resolve or upload Image 1
            var url1 = d1.imageURL ?? ""
            if url1.isEmpty, let data1 = d1.localImageData {
                url1 = try await ChamakAPI.uploadSourceImage(
                    wholesalerID: wholesalerID,
                    imageData: data1,
                    slot: 1,
                    mode: mode
                )
                self.selectedDesign1?.imageURL = url1
            }

            // Resolve or upload Image 2
            var url2 = d2.imageURL ?? ""
            if url2.isEmpty, let data2 = d2.localImageData {
                url2 = try await ChamakAPI.uploadSourceImage(
                    wholesalerID: wholesalerID,
                    imageData: data2,
                    slot: 2,
                    mode: mode
                )
                self.selectedDesign2?.imageURL = url2
            }

            guard !url1.isEmpty, !url2.isEmpty else {
                throw ChamakAPI.ChamakError(message: "Both designs must have valid uploaded images.")
            }

            // A set's third and fourth pieces, in the order they were chosen.
            var extraURLs: [String] = []
            if mode == .setCreation {
                for slot in [3, 4] {
                    guard let piece = design(inSlot: slot) else { continue }
                    var url = piece.imageURL ?? ""
                    if url.isEmpty, let data = piece.localImageData {
                        url = try await ChamakAPI.uploadSourceImage(
                            wholesalerID: wholesalerID,
                            imageData: data,
                            slot: slot,
                            mode: mode
                        )
                        if slot == 3 { selectedDesign3?.imageURL = url } else { selectedDesign4?.imageURL = url }
                    }
                    guard !url.isEmpty else {
                        throw ChamakAPI.ChamakError(message: "Every piece needs a valid uploaded image.")
                    }
                    extraURLs.append(url)
                }
            }

            var manifest: [ChamakAPI.SetSourceManifestItem]? = nil
            if mode == .setCreation {
                let pieces = setPieces
                let allURLs = [url1, url2] + extraURLs
                manifest = pieces.enumerated().map { index, piece in
                    let cType = piece.canonicalJewelleryType ?? "other"
                    let kind = piece.product != nil ? "catalogue" : "upload"
                    let prodID = piece.product?.id.lowercased()
                    let srcRef = index < allURLs.count ? allURLs[index] : (piece.imageURL ?? "")
                    return ChamakAPI.SetSourceManifestItem(
                        position: index + 1,
                        kind: kind,
                        product_id: prodID,
                        canonical_type: cType,
                        source_reference: srcRef
                    )
                }
            }

            let gen = try await ChamakAPI.createGeneration(
                wholesalerID: wholesalerID,
                source1URL: url1,
                source2URL: url2,
                extraSourceURLs: extraURLs,
                manifest: manifest,
                mode: mode
            )
            currentGeneration = gen

            if mode == .setCreation {
                stopQuoteRotation()
                step = .setStyling
            } else {
                try await ChamakAPI.triggerStage1Analysis(generationID: gen.id)
                // Start polling for Stage 1 analysis completion
                startPolling(generationID: gen.id, targetStatus: .awaitingInput)
            }
        } catch let err as ChamakAPI.InsufficientCreditsError {
            insufficientCreditsError = err
            showInsufficientCreditsSheet = true
            step = .catalogPicker
            stopQuoteRotation()
        } catch {
            errorMessage = error.localizedDescription
            step = .failed
            stopQuoteRotation()
        }
    }

    // MARK: - Stage 3 & 4: Submit Form & Generate

    /// Pairs each slider's weight with its human-readable attribute/feature
    /// text, so the backend can build the compiled prompt directly from
    /// this payload instead of re-deriving attribute meaning from an index.
    private func buildAttributeContext() -> [WeightedAttribute] {
        guard let attributes = currentGeneration?.stage1AnalysisJSON?.dynamicAttributes else { return [] }
        return attributes.map { attr in
            WeightedAttribute(
                id: attr.id,
                attribute: attr.name,
                image1Feature: attr.source1Feature,
                image2Feature: attr.source2Feature,
                weight: sliderValues[attr.id] ?? attr.defaultValue
            )
        }
    }

    func submitFormAndGenerate(wholesalerID: UUID, creditStore: CreditStore? = nil) async {
        guard let gen = currentGeneration else { return }

        // Idempotency: generate key if not already set, reuse across retries (§2.3)
        if pendingGenerateKey == nil {
            pendingGenerateKey = UUID().uuidString
        }

        isSubmitting = true
        step = .generating
        startQuoteRotation()

        let formInput = WholesalerFormInput(
            sliderWeights: sliderValues,
            attributeContext: buildAttributeContext(),
            note: noteText.isEmpty ? nil : noteText
        )

        do {
            try await ChamakAPI.submitFormAndGenerate(
                generationID: gen.id,
                wholesalerID: wholesalerID,
                formInput: formInput,
                note: composedSetNote,
                idempotencyKey: pendingGenerateKey
            )

            // Poll for generation completion
            startPolling(generationID: gen.id, targetStatus: .done, creditStore: creditStore)
        } catch let err as ChamakAPI.InsufficientCreditsError {
            // Rule §2.4 & §2.5: stay on slider form, form inputs preserved
            insufficientCreditsError = err
            showInsufficientCreditsSheet = true
            step = .sliderForm
            stopQuoteRotation()
        } catch {
            errorMessage = error.localizedDescription
            step = .failed
            stopQuoteRotation()
        }
        isSubmitting = false
    }

    // MARK: - Stage 3 & 4 (Set Creation): Submit Styling & Generate

    func submitSetAndGenerate(wholesalerID: UUID, creditStore: CreditStore? = nil) async {
        guard let gen = currentGeneration else { return }

        if pendingGenerateKey == nil {
            pendingGenerateKey = UUID().uuidString
        }

        isSubmitting = true
        step = .generating
        startQuoteRotation()

        do {
            try await ChamakAPI.submitSetAndGenerate(
                generationID: gen.id,
                wholesalerID: wholesalerID,
                backdrop: selectedBackdrop,
                note: composedSetNote,
                idempotencyKey: pendingGenerateKey
            )
            startPolling(generationID: gen.id, targetStatus: .done, creditStore: creditStore)
        } catch let err as ChamakAPI.InsufficientCreditsError {
            insufficientCreditsError = err
            showInsufficientCreditsSheet = true
            step = .setStyling
            stopQuoteRotation()
        } catch {
            errorMessage = error.localizedDescription
            step = .failed
            stopQuoteRotation()
        }
        isSubmitting = false
    }

    // MARK: - Revise & Retry (back to the right earlier step, keeping state)

    /// Returns to whichever step still has valid data to retry from,
    /// instead of always assuming stage 1 already succeeded.
    func reviseAndRetry() {
        stopQuoteRotation()
        if mode == .setCreation {
            step = currentGeneration != nil ? .setStyling : .catalogPicker
        } else {
            step = currentGeneration?.stage1AnalysisJSON != nil ? .sliderForm : .catalogPicker
        }
    }

    // MARK: - Regenerate (Re-uses Stage 1 analysis)

    func regenerate(wholesalerID: UUID, creditStore: CreditStore? = nil) async {
        guard let gen = currentGeneration else { return }

        // Deliberate re-roll: generate a NEW UUID so server charges re-roll fee (§2.3)
        pendingGenerateKey = UUID().uuidString

        step = .generating
        startQuoteRotation()

        let formInput = WholesalerFormInput(
            sliderWeights: sliderValues,
            attributeContext: buildAttributeContext(),
            note: noteText.isEmpty ? nil : noteText
        )

        do {
            try await ChamakAPI.submitFormAndGenerate(
                generationID: gen.id,
                wholesalerID: wholesalerID,
                formInput: formInput,
                note: noteText.isEmpty ? nil : noteText,
                idempotencyKey: pendingGenerateKey
            )
            startPolling(generationID: gen.id, targetStatus: .done, creditStore: creditStore)
        } catch let err as ChamakAPI.InsufficientCreditsError {
            insufficientCreditsError = err
            showInsufficientCreditsSheet = true
            step = .sliderForm
            stopQuoteRotation()
        } catch {
            errorMessage = error.localizedDescription
            step = .failed
            stopQuoteRotation()
        }
    }

    /// Set Creation's re-roll — same generation row, same backdrop/note,
    /// fresh idempotency key. The backend prices this as `chamak.reroll`
    /// automatically (it counts prior debits against `generation_id`), same
    /// as Fusion's `regenerate`.
    func regenerateSet(wholesalerID: UUID, creditStore: CreditStore? = nil) async {
        guard let gen = currentGeneration else { return }

        pendingGenerateKey = UUID().uuidString

        step = .generating
        startQuoteRotation()

        do {
            try await ChamakAPI.submitSetAndGenerate(
                generationID: gen.id,
                wholesalerID: wholesalerID,
                backdrop: selectedBackdrop,
                note: noteText.isEmpty ? nil : noteText,
                idempotencyKey: pendingGenerateKey
            )
            startPolling(generationID: gen.id, targetStatus: .done, creditStore: creditStore)
        } catch let err as ChamakAPI.InsufficientCreditsError {
            insufficientCreditsError = err
            showInsufficientCreditsSheet = true
            step = .setStyling
            stopQuoteRotation()
        } catch {
            errorMessage = error.localizedDescription
            step = .failed
            stopQuoteRotation()
        }
    }

    // MARK: - Polling Engine

    private func startPolling(
        generationID: UUID,
        targetStatus: ChamakStatus,
        creditStore: CreditStore? = nil
    ) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var attempts = 0
            var consecutiveFailures = 0
            var lastPollError: Error?
            // ~240s ceiling (80 × 3s). The old budget was 40 × 2.5s = 100s,
            // which was sized for Nanobana. OpenAI's median run is far
            // slower and 2K output slower still, so the old ceiling would
            // expire on generations that actually succeed — showing the
            // wholesaler a failure for an image they were already charged
            // for, and which is sitting completed in their gallery.
            while attempts < 80 {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                guard let self, !Task.isCancelled else { return }
                attempts += 1

                do {
                    let updated = try await ChamakAPI.fetchGeneration(generationID: generationID)
                    self.currentGeneration = updated

                    if updated.status == targetStatus {
                        if targetStatus == .awaitingInput {
                            self.stopQuoteRotation()
                            self.setupSlidersFromAnalysis(updated.stage1AnalysisJSON)
                            self.step = .sliderForm
                        } else if targetStatus == .done {
                            self.pendingGenerateKey = nil // Cleared on successful generation

                            // Resolve the signed URL BEFORE any teardown and
                            // before `step` moves. Everything after this await
                            // used to depend on a task that had already
                            // cancelled itself.
                            await self.signOutputs(for: updated)

                            self.stopQuoteRotation()
                            self.step = .result

                            // Refresh wallet and show deduction toast (Task i7f)
                            if let creditStore {
                                let prevBalance = creditStore.wallet?.available
                                await creditStore.refresh()
                                if let newBalance = creditStore.wallet?.available, let prev = prevBalance, prev > newBalance {
                                    let diff = prev - newBalance
                                    self.toastMessage = "−\(diff) credits · \(newBalance) left"
                                    self.showToast = true
                                }
                            }
                        }
                        return
                    } else if updated.status == .failed {
                        self.stopQuoteRotation()
                        self.errorMessage = updated.failureUserMessage
                        self.step = .failed
                        return
                    }
                } catch {
                    // A single failure here is genuinely non-fatal — a poll
                    // that misses one tick will catch the row on the next.
                    // A run of them is not: it means every read is failing
                    // and the loop is spinning blind for the full 240s before
                    // claiming the generation was merely slow. Remember it, so
                    // the timeout below can say which of the two happened.
                    consecutiveFailures += 1
                    lastPollError = error
                    continue
                }

                // A successful read resets the streak.
                consecutiveFailures = 0
            }

            // Timeout fallback
            guard let self, !Task.isCancelled else { return }
            self.stopQuoteRotation()
            if consecutiveFailures >= 5 {
                // Not slowness — we never managed to read the row. Saying
                // "taking longer than expected" here sends the wholesaler to
                // wait for something that may already be finished.
                #if DEBUG
                self.errorMessage = "Couldn't read this generation's status. It may still have completed — check your gallery.\n\n[debug] \(lastPollError.map(String.init(describing:)) ?? "unknown")"
                #else
                self.errorMessage = "Couldn't read this generation's status. It may still have completed — check your gallery."
                #endif
            } else {
                self.errorMessage = "Generation is taking longer than expected. Please check your gallery shortly."
            }
            self.step = .failed
        }
    }

    private func setupSlidersFromAnalysis(_ analysis: Stage1Analysis?) {
        guard let analysis else { return }
        for attr in analysis.dynamicAttributes {
            if sliderValues[attr.id] == nil {
                sliderValues[attr.id] = attr.defaultValue
            }
        }
    }

    // MARK: - Quote Rotation

    private func startQuoteRotation() {
        quoteTask?.cancel()
        activeQuoteIndex = 0
        quoteTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
                guard let self, !Task.isCancelled else { return }
                self.activeQuoteIndex = (self.activeQuoteIndex + 1) % ChamakQuote.quotes.count
            }
        }
    }

    private func stopQuoteRotation() {
        quoteTask?.cancel()
        quoteTask = nil
    }

    /// Cancelling the poll is now separate from stopping the quotes.
    ///
    /// It used not to be, and the poll loop called `stopQuoteRotation` on
    /// success — from inside the poll task, so the task cancelled itself and
    /// then carried on running. That was survivable for `.awaitingInput`,
    /// which sets `step` immediately afterwards with nothing to await. It was
    /// not survivable for `.done`, which awaits a signed URL first and only
    /// then assigns `step = .result`: that continuation never landed, so the
    /// wholesaler sat on a frozen generating screen while the finished image
    /// was already in their gallery.
    ///
    /// Never call this from inside the poll task. The loop `return`s when it
    /// is finished, which ends the task on its own.
    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Feedback

    func submitFeedback() async {
        guard let gen = currentGeneration else { return }
        do {
            try await ChamakAPI.submitFeedback(
                generationID: gen.id,
                satisfied: feedbackSatisfied,
                whatWentWrong: feedbackText.isEmpty ? nil : feedbackText
            )
            feedbackSubmitted = true
            isShowingFeedbackSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Navigation Helpers

    func resetToPicker() {
        stopQuoteRotation()
        // Explicit now that `stopQuoteRotation` no longer does it implicitly.
        // Abandoning the flow must abandon the poll with it, or a stale task
        // keeps writing `step` under a wholesaler who has moved on.
        stopPolling()
        selectedDesign1 = nil
        selectedDesign2 = nil
        selectedDesign3 = nil
        selectedDesign4 = nil
        currentGeneration = nil
        signedOutputImageURL = nil
        signedFullOutputImageURL = nil
        signedOutputImageURLs = []
        sliderValues = [:]
        noteText = ""
        selectedBackdrop = .velvetBust
        selectedStylingChips = []
        errorMessage = nil
        step = .catalogPicker
        // `mode` deliberately left alone — "New Set"/"New Combine" should stay
        // in whichever mode the wholesaler opened this flow with.
    }

    func openGalleryItem(_ item: ChamakGeneration) async {
        currentGeneration = item
        errorMessage = item.status == .failed ? item.failureUserMessage : nil
        await signOutputs(for: item)
        // A failed row has no output to wait for; without this it opened on a
        // result card stuck on "loading" forever.
        step = item.status == .failed ? .failed : .result
    }
}
