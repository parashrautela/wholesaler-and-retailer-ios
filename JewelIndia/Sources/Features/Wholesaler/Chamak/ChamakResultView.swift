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
                VStack(spacing: Spacing.lg) {
                    if vm.step == .failed {
                        failureCard
                    } else {
                        mainResultSection
                        sourceDesignsSection
                    }
                }
                .padding(.horizontal, Spacing.base)
                .padding(.top, Spacing.base)
                .padding(.bottom, 120)
                .frame(maxWidth: isRegularWidth ? 880 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            bottomActionBar
        }
        .background(Color(hex: 0xF7F7F6))
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

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button {
                vm.resetToPicker()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.dark)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Text("Final Design")
                .font(.cirka(isRegularWidth ? 26 : 22, weight: .bold))
                .foregroundStyle(Palette.dark)

            Spacer()

            Button {
                vm.isShowingFeedbackSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 12))
                    Text(vm.feedbackSubmitted ? "Feedback Sent" : "Feedback")
                        .font(.manrope(12, weight: .bold))
                }
                .foregroundStyle(Color(hex: 0xB4833E))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(hex: 0xFDF8EE), in: Capsule())
                .overlay {
                    Capsule().stroke(Color(hex: 0xF6E8CD), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: isRegularWidth ? 880 : .infinity)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.6)
        }
    }

    // MARK: - Main Result Section

    private var isSet: Bool { vm.mode == .setCreation }

    private var mainResultSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(isSet ? "Your Matched Set" : "New Direction")
                    .font(.manrope(16, weight: .bold))
                    .foregroundStyle(Palette.dark)

                Spacer()

                Menu {
                    Button {
                        vm.reviseAndRetry()
                    } label: {
                        Label("Adjust", systemImage: "slider.horizontal.2")
                    }

                    Button(role: .destructive) {
                        vm.isShowingFeedbackSheet = true
                    } label: {
                        Label("Report", systemImage: "exclamationmark.bubble")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: 0x5E5D5A))
                        .frame(width: 32, height: 32)
                }
            }

            ZStack(alignment: .topTrailing) {
                if let url = vm.signedFullOutputImageURL ?? vm.signedOutputImageURL {
                    Button {
                        openViewer(on: "result")
                    } label: {
                        Color(hex: 0xF9F9F8)
                            .aspectRatio(isRegularWidth ? 1.25 : 1.05, contentMode: .fit)
                            .overlay {
                                ProtectedImageView(url: url, contentMode: .scaleAspectFit)
                                    .padding(isRegularWidth ? 32 : 16)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)

                    Button {
                        openViewer(on: "result")
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.dark)
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.95), in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    }
                    .padding(12)
                } else {
                    Color(hex: 0xF9FAFB)
                        .aspectRatio(isRegularWidth ? 1.25 : 1.05, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            VStack(spacing: 8) {
                                ProgressView().tint(Color(hex: 0xCA8A04))
                                Text("Loading private image...")
                                    .font(.manrope(13))
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0xE7E5E4), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        }
    }

    // MARK: - Source Designs Section

    private var sourceDesignsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(isSet ? "Pieces in this Set" : "Core Design")
                .font(.manrope(16, weight: .bold))
                .foregroundStyle(Palette.dark)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: isRegularWidth ? min(sourcePreviews.count, 4) : 2),
                spacing: Spacing.md
            ) {
                ForEach(sourcePreviews) { preview in
                    sourceDesignCard(preview)
                }
            }
        }
    }

    private func sourceDesignCard(_ preview: SourcePreview) -> some View {
        Button {
            openViewer(on: preview.id)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Color(hex: 0xF3F4F6)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if let url = preview.url {
                                ProtectedImageView(url: url)
                            }
                        }
                        .clipped()

                    if preview.url != nil {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.dark)
                            .frame(width: 26, height: 26)
                            .background(.white.opacity(0.9), in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                            .padding(8)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.title)
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Palette.dark)
                    if let caption = preview.caption {
                        Text(caption)
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xF9F9F8))
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).stroke(Color(hex: 0xE7E5E4), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.02), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Failure Card

    private var failureCard: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color(hex: 0xEF4444))

            VStack(spacing: Spacing.xs) {
                Text((vm.currentGeneration?.contentFlagHit ?? vm.currentGeneration?.stage1AnalysisJSON?.contentFlag) == .notJewelry
                     ? "Jewellery Not Detected"
                     : "Generation Incomplete")
                    .font(.cirka(22, weight: .bold))
                    .foregroundStyle(Palette.dark)

                Text(vm.errorMessage ?? "The AI model encountered an unexpected issue while synthesizing your piece.")
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
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Palette.dark, in: Capsule())
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0xFECACA), lineWidth: 1)
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        let rerollCost = credits.cost(for: "chamak.reroll")

        return VStack(spacing: 0) {
            Divider().opacity(0.6)

            VStack(spacing: Spacing.sm) {
                if vm.step == .result,
                   let generation = vm.currentGeneration,
                   let url = vm.signedFullOutputImageURL ?? vm.signedOutputImageURL {
                    ChamakExportButton(generationID: generation.id.uuidString, imageURL: url)
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
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(Palette.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white, in: Capsule())
                        .overlay {
                            Capsule().stroke(Color(hex: 0xD1D5DB), lineWidth: 1)
                        }
                    }
                    .disabled(vm.isSubmitting)
                } else if vm.step == .failed {
                    Button {
                        vm.reviseAndRetry()
                    } label: {
                        Text("Adjust & Try Again")
                            .font(.manrope(14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Palette.dark, in: Capsule())
                    }
                }
            }
            .frame(maxWidth: isRegularWidth ? 640 : .infinity)
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.md)
        }
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private var source1URL: URL? {
        (vm.currentGeneration?.sourceImage1URL ?? vm.selectedDesign1?.imageURL).flatMap(URL.init(string:))
    }

    private var source2URL: URL? {
        (vm.currentGeneration?.sourceImage2URL ?? vm.selectedDesign2?.imageURL).flatMap(URL.init(string:))
    }

    private var source3URL: URL? {
        (vm.currentGeneration?.sourceImage3URL ?? vm.selectedDesign3?.imageURL).flatMap(URL.init(string:))
    }

    private var source4URL: URL? {
        (vm.currentGeneration?.sourceImage4URL ?? vm.selectedDesign4?.imageURL).flatMap(URL.init(string:))
    }

    private struct SourcePreview: Identifiable {
        let id: String
        let title: String
        let caption: String?
        let url: URL?
        let accentColor: Color
    }

    private var sourcePreviews: [SourcePreview] {
        var previews = [
            SourcePreview(
                id: "source",
                title: isSet ? (vm.selectedDesign1?.title ?? "Piece 1") : (vm.selectedDesign1?.title ?? "Core design"),
                caption: isSet ? "Core piece" : "Keeps its identity",
                url: source1URL,
                accentColor: Color(hex: 0xCA8A04)
            ),
            SourcePreview(
                id: "upgrade",
                title: isSet ? (vm.selectedDesign2?.title ?? "Piece 2") : (vm.selectedDesign2?.title ?? "New direction"),
                caption: isSet ? "Second piece" : "New expression",
                url: source2URL,
                accentColor: Color(hex: 0x3B82F6)
            )
        ]

        if isSet {
            previews += [
                SourcePreview(id: "piece3", title: "Piece 3", caption: "Optional", url: source3URL, accentColor: Color(hex: 0x10B981)),
                SourcePreview(id: "piece4", title: "Piece 4", caption: "Optional", url: source4URL, accentColor: Color(hex: 0xE11D48))
            ]
        }

        return previews.filter { $0.url != nil }
    }

    private var viewerImages: [ChamakViewerImage] {
        var images: [ChamakViewerImage] = []
        if let output = vm.signedFullOutputImageURL ?? vm.signedOutputImageURL {
            images.append(ChamakViewerImage(
                id: "result", label: isSet ? "Your Set" : "Final Design", url: output, isResult: true
            ))
        }
        for preview in sourcePreviews {
            if let url = preview.url {
                images.append(ChamakViewerImage(
                    id: preview.id, label: preview.title, url: url, isResult: false
                ))
            }
        }
        return images
    }

    private func openViewer(on imageID: String) {
        let images = viewerImages
        guard let index = images.firstIndex(where: { $0.id == imageID }) else { return }
        viewerRequest = ChamakViewerRequest(images: images, startIndex: index)
    }
}
