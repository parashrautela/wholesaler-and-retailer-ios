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
    /// "New Set"/"New Fusion" stays in the mode the wholesaler opened.
    var mode: ChamakMode = .fusion

    // Data
    var catalogProducts: [Product] = []
    var galleryGenerations: [ChamakGeneration] = []
    /// Signed thumbnails for `galleryGenerations`, keyed by generation id.
    /// Outputs live in a private bucket, so a tile has nothing to show until
    /// its path has been signed.
    var galleryThumbnailURLs: [UUID: URL] = [:]
    var selectedDesign1: ChamakDesignItem?
    var selectedDesign2: ChamakDesignItem?
    var currentGeneration: ChamakGeneration?
    var signedOutputImageURL: URL?

    // Form inputs
    var sliderValues: [String: Double] = [:]
    var noteText: String = ""
    var selectedBackdrop: SetBackdrop = .velvetBust

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

        async let productsTask = ChamakAPI.fetchWholesalerProducts(wholesalerID: wholesalerID)
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
            galleryErrorMessage = Self.galleryFailureCopy(error)
        }
    }

    private func signGalleryThumbnails() async {
        let paths = galleryGenerations.compactMap(\.outputImageURL)
        let signed = await ChamakAPI.getSignedURLs(paths: paths)
        var byID: [UUID: URL] = [:]
        for gen in galleryGenerations {
            if let path = gen.outputImageURL, let url = signed[path] {
                byID[gen.id] = url
            }
        }
        galleryThumbnailURLs = byID
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

    func selectProduct(_ product: Product) {
        if selectedDesign1?.product?.id == product.id {
            selectedDesign1 = nil
        } else if selectedDesign2?.product?.id == product.id {
            selectedDesign2 = nil
        } else if selectedDesign1 == nil {
            selectedDesign1 = .from(product: product)
        } else if selectedDesign2 == nil {
            selectedDesign2 = .from(product: product)
        } else {
            // Replace design 2 by default if both are chosen
            selectedDesign2 = .from(product: product)
        }
    }

    func setCustomImage(data: Data, forSlot slot: Int) {
        if slot == 1 {
            selectedDesign1 = .from(imageData: data, slot: 1)
        } else {
            selectedDesign2 = .from(imageData: data, slot: 2)
        }
    }

    var canStartAnalysis: Bool {
        guard let d1 = selectedDesign1, let d2 = selectedDesign2 else { return false }
        guard d1.hasImage && d2.hasImage else { return false }
        guard d1.id != d2.id else { return false }
        // Two custom uploads always get distinct random ids, so only a
        // matching contentHash (set for direct uploads only) catches the
        // same photo being picked for both slots.
        if let h1 = d1.contentHash, let h2 = d2.contentHash, h1 == h2 { return false }
        return true
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

            let gen = try await ChamakAPI.createGeneration(
                wholesalerID: wholesalerID,
                source1URL: url1,
                source2URL: url2,
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
                note: noteText.isEmpty ? nil : noteText,
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
                            if let output = updated.outputImageURL {
                                self.signedOutputImageURL = await ChamakAPI.getSignedURL(path: output)
                            }

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
                        self.errorMessage = "AI generation could not complete. Please provide feedback below."
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
        currentGeneration = nil
        signedOutputImageURL = nil
        sliderValues = [:]
        noteText = ""
        selectedBackdrop = .velvetBust
        errorMessage = nil
        step = .catalogPicker
        // `mode` deliberately left alone — "New Set"/"New Fusion" should stay
        // in whichever mode the wholesaler opened this flow with.
    }

    func openGalleryItem(_ item: ChamakGeneration) async {
        currentGeneration = item
        if let out = item.outputImageURL {
            signedOutputImageURL = await ChamakAPI.getSignedURL(path: out)
        }
        // A failed row has no output to wait for; without this it opened on a
        // result card stuck on "loading" forever.
        step = item.status == .failed ? .failed : .result
    }
}
