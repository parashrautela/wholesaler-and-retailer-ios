import SwiftUI

struct ChamakResultView: View {
    @Environment(CreditStore.self) private var credits
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var vm: ChamakViewModel
    let wholesalerID: UUID

    @State private var viewerRequest: ChamakViewerRequest?

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                Group {
                    if vm.step == .failed {
                        failureCard
                    } else if isRegularWidth {
                        // iPad: the result is the hero. Stacked full-width, the
                        // two design tiles grew to ~370pt squares and dwarfed
                        // the output beneath them.
                        HStack(alignment: .top, spacing: Spacing.lg) {
                            fusedResultCard
                                .frame(maxWidth: .infinity)
                            VStack(spacing: Spacing.lg) {
                                sourceDesignsRow
                                promptInfoCard
                            }
                            .frame(width: 340)
                        }
                    } else {
                        VStack(spacing: Spacing.lg) {
                            sourceDesignsRow
                            fusedResultCard
                            promptInfoCard
                        }
                    }
                }
                .padding(.horizontal, Spacing.base)
                .padding(.top, Spacing.base)
                .padding(.bottom, Spacing.huge)
            }
            .scrollIndicators(.hidden)

            bottomActionBar
        }
        .background(Color(hex: 0xFAFAFA))
        .sheet(isPresented: $vm.isShowingFeedbackSheet) {
            ChamakFeedbackSheet(vm: vm)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $vm.showInsufficientCreditsSheet) {
            InsufficientCreditsSheet(error: vm.insufficientCreditsError)
                .presentationDetents([.medium])
        }
        .fullScreenCover(item: $viewerRequest) { request in
            ChamakImageViewer(images: request.images, startIndex: request.startIndex)
        }
    }

    // MARK: - Full-Screen Viewer

    private var isSet: Bool { vm.mode == .setCreation }

    private var source1URL: URL? {
        (vm.currentGeneration?.sourceImage1URL ?? vm.selectedDesign1?.imageURL).flatMap(URL.init(string:))
    }

    private var source2URL: URL? {
        (vm.currentGeneration?.sourceImage2URL ?? vm.selectedDesign2?.imageURL).flatMap(URL.init(string:))
    }

    /// Source, upgrade, then the result — the order the thumbnails read in.
    private var viewerImages: [ChamakViewerImage] {
        var images: [ChamakViewerImage] = []
        if let source1URL {
            images.append(ChamakViewerImage(
                id: "source", label: isSet ? "Piece 1" : "Source", url: source1URL, isResult: false
            ))
        }
        if let source2URL {
            images.append(ChamakViewerImage(
                id: "upgrade", label: isSet ? "Piece 2" : "Upgrade", url: source2URL, isResult: false
            ))
        }
        // Full size here: this is the screen where a wholesaler zooms in to
        // inspect the stones. Falls back to the screen-sized copy until the
        // bigger one has been signed.
        if let output = vm.signedFullOutputImageURL ?? vm.signedOutputImageURL {
            images.append(ChamakViewerImage(
                id: "result", label: isSet ? "Your Set" : "Result", url: output, isResult: true
            ))
        }
        return images
    }

    private func openViewer(on imageID: String) {
        let images = viewerImages
        guard let index = images.firstIndex(where: { $0.id == imageID }) else { return }
        viewerRequest = ChamakViewerRequest(images: images, startIndex: index)
    }

    private var expandGlyph: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.dark)
            .frame(width: 26, height: 26)
            .background(.white.opacity(0.9), in: .circle)
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .padding(6)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button {
                vm.resetToPicker()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left")
                    Text(vm.mode == .setCreation ? "New Set" : "New Fusion")
                }
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)
            }

            Spacer()

            Text(vm.mode == .setCreation ? "Set Creation Result" : "Chamak Fusion Result")
                .font(.cirka(18, weight: .bold))
                .foregroundStyle(Palette.dark)

            Spacer()

            Button {
                vm.step = .gallery
            } label: {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: 0xBB8651))
            }
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.md)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Source Designs Row

    private var sourceDesignsRow: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(isSet ? "Pieces Used" : "Designs Used")
                .font(.manrope(12, weight: .bold))
                .foregroundStyle(Palette.muted)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: Spacing.sm) {
                sourceTile(
                    title: isSet ? "Piece 1" : "Source design",
                    caption: isSet ? nil : "Keeps its strengths",
                    url: source1URL,
                    badgeColor: Color(hex: 0xD4AF37),
                    viewerID: "source"
                )

                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 56)

                sourceTile(
                    title: isSet ? "Piece 2" : "Upgrade design",
                    caption: isSet ? nil : "Brings the upgrades",
                    url: source2URL,
                    badgeColor: Color(hex: 0x3B82F6),
                    viewerID: "upgrade"
                )
            }
        }
        .padding(Spacing.base)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private func sourceTile(
        title: String,
        caption: String?,
        url: URL?,
        badgeColor: Color,
        viewerID: String
    ) -> some View {
        Button {
            openViewer(on: viewerID)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Color(hex: 0xF3F4F6)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let url {
                            ProtectedImageView(url: url)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(alignment: .bottomTrailing) {
                        if url != nil { expandGlyph }
                    }

                Text(title)
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(badgeColor)
                    .padding(.top, 2)

                if let caption {
                    Text(caption)
                        .font(.manrope(11))
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(url == nil)
        .accessibilityLabel("\(title), view full screen")
    }

    // MARK: - Fused Result Card

    private var fusedResultCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(vm.mode == .setCreation ? "Your Matched Set" : "Fused Design 3")
                    .font(.cirka(22, weight: .bold))
                    .foregroundStyle(Palette.dark)
                Spacer()
                Text("Studio Render")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Color(hex: 0xBB8651))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: 0xFFFBF4), in: .capsule)
                    .overlay {
                        Capsule().stroke(Color(hex: 0xF3E8D6), lineWidth: 1)
                    }
            }

            ZStack {
                if !vm.signedOutputImageURLs.isEmpty {
                    Button {
                        openViewer(on: "result")
                    } label: {
                        TabView {
                            ForEach(Array(vm.signedOutputImageURLs.enumerated()), id: \.offset) { index, url in
                                ProtectedImageView(url: url, contentMode: .scaleAspectFit)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: isRegularWidth ? 520 : 280)
                                    .background(Color(hex: 0xF9FAFB))
                                    .clipShape(.rect(cornerRadius: 12))
                                    .overlay(alignment: .topTrailing) {
                                        Text("\(index + 1) / \(vm.signedOutputImageURLs.count)")
                                            .font(.manrope(11, weight: .bold))
                                            .foregroundStyle(Palette.dark)
                                            .padding(.horizontal, 8).padding(.vertical, 5)
                                            .background(.white.opacity(0.9), in: Capsule())
                                            .padding(10)
                                    }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                        .frame(minHeight: isRegularWidth ? 520 : 280)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(alignment: .bottomTrailing) { expandGlyph }
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("View result full screen")
                } else if let url = vm.signedOutputImageURL {
                    ProtectedImageView(url: url, contentMode: .scaleAspectFit)
                        .frame(maxWidth: .infinity).frame(minHeight: isRegularWidth ? 520 : 280)
                        .background(Color(hex: 0xF9FAFB)).clipShape(.rect(cornerRadius: 12))
                } else {
                    Color(hex: 0xF9FAFB)
                        .frame(maxWidth: .infinity)
                        .frame(height: isRegularWidth ? 520 : 280)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Color(hex: 0xBB8651))
                                Text("Private signed image loading...")
                                    .font(.manrope(13))
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                }
            }

            exportControl

            Text(
                vm.mode == .setCreation
                    ? "This set photo lives in your Chamak Gallery and is not published to your public catalogue."
                    : "This fused output lives in your Chamak Gallery and is not published to your public catalogue."
            )
            .font(.manrope(11))
            .foregroundStyle(Palette.muted)
        }
        .padding(Spacing.base)
        .background(Color.white, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
    }

    /// Its own property: inline, it tips `fusedResultCard` past what the type
    /// checker will solve in one expression.
    @ViewBuilder
    private var exportControl: some View {
        if let generation = vm.currentGeneration, generation.status == .done,
           let url = vm.signedFullOutputImageURL ?? vm.signedOutputImageURL {
            ChamakExportButton(generationID: generation.id.uuidString, imageURL: url)
        }
    }

    // MARK: - Prompt Info Card

    private var promptInfoCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Traceability")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .textCase(.uppercase)
                Spacer()
                Text("Version: \(vm.currentGeneration?.promptVersion ?? "v1.0-chamak")")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }

            if let id = vm.currentGeneration?.id {
                traceabilityRow(label: "Generation ID", value: id.uuidString)
            }
            if let createdAt = vm.currentGeneration?.createdAt {
                traceabilityRow(label: "Created", value: createdAt)
            }

            if let attributes = vm.currentGeneration?.wholesalerFormJSON?.attributeContext, !attributes.isEmpty {
                traceabilitySection(title: "Toggle Values Used") {
                    ForEach(attributes, id: \.id) { attr in
                        Text("\(attr.attribute): \(Int(attr.weight * 100))% toward Design \(attr.weight >= 0.5 ? "2" : "1")")
                            .font(.manrope(11))
                            .foregroundStyle(Palette.dark.opacity(0.8))
                    }
                }
            }

            if let note = vm.currentGeneration?.noteText, !note.isEmpty {
                traceabilitySection(title: "Additional Prompt") {
                    Text(note)
                        .font(.manrope(11))
                        .foregroundStyle(Palette.dark.opacity(0.8))
                }
            }

            // The web result screen never shows the compiled prompt for Set
            // Creation (`SetCreationResultStep.jsx` — output image, piece
            // compare, and the note only), so this stays Fusion-only.
            if vm.mode != .setCreation, let prompt = vm.currentGeneration?.compiledPromptText, !prompt.isEmpty {
                traceabilitySection(title: "Combined Prompt Sent to AI") {
                    Text(prompt)
                        .font(.manrope(12))
                        .foregroundStyle(Palette.dark.opacity(0.8))
                }
            }
        }
        .padding(Spacing.base)
        .background(Color(hex: 0xF9FAFB), in: .rect(cornerRadius: 10))
    }

    private func traceabilityRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Palette.muted)
            Spacer()
            Text(value)
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Palette.dark.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
    }

    private func traceabilitySection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.manrope(11, weight: .bold))
                .foregroundStyle(Palette.dark)
            content()
        }
    }

    // MARK: - Failure Card

    private var failureCard: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color(hex: 0xEF4444))

            VStack(spacing: Spacing.xs) {
                Text("Generation Incomplete")
                    .font(.cirka(22, weight: .bold))
                    .foregroundStyle(Palette.dark)

                Text(vm.errorMessage ?? "The AI model encountered an unexpected issue while fusing your designs. No auto-retries are performed.")
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }

            Button {
                vm.isShowingFeedbackSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                    Text("Report What Went Wrong")
                }
                .font(.manrope(14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Palette.dark, in: .rect(cornerRadius: 8))
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: 0xFEE2E2), lineWidth: 1)
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        let rerollCost = credits.cost(for: "chamak.reroll")

        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: Spacing.sm) {
                Button {
                    vm.isShowingFeedbackSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.fill")
                        Text(vm.feedbackSubmitted ? "Feedback Sent" : "Feedback")
                    }
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: 0xF3F4F6), in: .rect(cornerRadius: 10))
                }

                Spacer(minLength: 4)

                Button {
                    vm.reviseAndRetry()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.2")
                        Text("Adjust")
                    }
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white, in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Palette.border, lineWidth: 1)
                    }
                }

                if vm.step == .result {
                    Button {
                        Task {
                            if vm.mode == .setCreation {
                                await vm.regenerateSet(wholesalerID: wholesalerID, creditStore: credits)
                            } else {
                                await vm.regenerate(wholesalerID: wholesalerID, creditStore: credits)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            if let rerollCost, rerollCost > 0 {
                                Text("Try Again · \(rerollCost) credits")
                            } else {
                                Text("Try Again")
                            }
                        }
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(hex: 0x111827), in: .rect(cornerRadius: 10))
                    }
                    .disabled(vm.isSubmitting)
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.md)
            .background(Color.white)
        }
    }
}
