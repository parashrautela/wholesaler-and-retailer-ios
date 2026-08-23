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
        case generating
        case result
        case failed
        case gallery
    }

    var step: Step = .catalogPicker

    // Data
    var catalogProducts: [Product] = []
    var galleryGenerations: [ChamakGeneration] = []
    var selectedDesign1: ChamakDesignItem?
    var selectedDesign2: ChamakDesignItem?
    var currentGeneration: ChamakGeneration?
    var signedOutputImageURL: URL?

    // Form inputs
    var sliderValues: [String: Double] = [:]
    var noteText: String = ""

    // Idempotency & Credits (Rules §2.3, §2.4, Task i7)
    private var pendingGenerateKey: String?
    var insufficientCreditsError: ChamakAPI.InsufficientCreditsError?
    var showInsufficientCreditsSheet: Bool = false
    var toastMessage: String?
    var showToast: Bool = false

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

        galleryGenerations = (try? await galleryTask) ?? []
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

    // MARK: - Stage 1 Vision Analysis

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
                    slot: 1
                )
                self.selectedDesign1?.imageURL = url1
            }

            // Resolve or upload Image 2
            var url2 = d2.imageURL ?? ""
            if url2.isEmpty, let data2 = d2.localImageData {
                url2 = try await ChamakAPI.uploadSourceImage(
                    wholesalerID: wholesalerID,
                    imageData: data2,
                    slot: 2
                )
                self.selectedDesign2?.imageURL = url2
            }

            guard !url1.isEmpty, !url2.isEmpty else {
                throw ChamakAPI.ChamakError(message: "Both designs must have valid uploaded images.")
            }

            let gen = try await ChamakAPI.createGeneration(
                wholesalerID: wholesalerID,
                source1URL: url1,
                source2URL: url2
            )
            currentGeneration = gen

            try await ChamakAPI.triggerStage1Analysis(generationID: gen.id)

            // Start polling for Stage 1 analysis completion
            startPolling(generationID: gen.id, targetStatus: .awaitingInput)
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

    // MARK: - Revise & Retry (back to the right earlier step, keeping state)

    /// Returns to whichever step still has valid data to retry from,
    /// instead of always assuming stage 1 already succeeded.
    func reviseAndRetry() {
        stopQuoteRotation()
        step = currentGeneration?.stage1AnalysisJSON != nil ? .sliderForm : .catalogPicker
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

    // MARK: - Polling Engine

    private func startPolling(
        generationID: UUID,
        targetStatus: ChamakStatus,
        creditStore: CreditStore? = nil
    ) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var attempts = 0
            while attempts < 40 {
                try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
                guard let self, !Task.isCancelled else { return }
                attempts += 1

                do {
                    let updated = try await ChamakAPI.fetchGeneration(generationID: generationID)
                    self.currentGeneration = updated

                    if updated.status == targetStatus {
                        self.stopQuoteRotation()
                        if targetStatus == .awaitingInput {
                            self.setupSlidersFromAnalysis(updated.stage1AnalysisJSON)
                            self.step = .sliderForm
                        } else if targetStatus == .done {
                            self.pendingGenerateKey = nil // Cleared on successful generation
                            if let output = updated.outputImageURL {
                                self.signedOutputImageURL = await ChamakAPI.getSignedURL(path: output)
                            }
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
                    // Non-fatal, continue polling
                }
            }

            // Timeout fallback
            guard let self, !Task.isCancelled else { return }
            self.stopQuoteRotation()
            self.errorMessage = "Generation is taking longer than expected. Please check your gallery shortly."
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
        selectedDesign1 = nil
        selectedDesign2 = nil
        currentGeneration = nil
        signedOutputImageURL = nil
        sliderValues = [:]
        noteText = ""
        errorMessage = nil
        step = .catalogPicker
    }

    func openGalleryItem(_ item: ChamakGeneration) async {
        currentGeneration = item
        if let out = item.outputImageURL {
            signedOutputImageURL = await ChamakAPI.getSignedURL(path: out)
        }
        step = .result
    }
}
