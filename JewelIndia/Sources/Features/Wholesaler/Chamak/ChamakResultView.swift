import SwiftUI

struct ChamakResultView: View {
    @Bindable var vm: ChamakViewModel
    let wholesalerID: UUID

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if vm.step == .failed {
                        failureCard
                    } else {
                        sourceDesignsRow
                        fusedResultCard
                        promptInfoCard
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
        .alert("Daily AI Quota Reached", isPresented: $vm.showQuotaAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You have reached your daily Chamak generation limit. Please try again tomorrow.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button {
                vm.resetToPicker()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left")
                    Text("New Fusion")
                }
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)
            }

            Spacer()

            Text("Chamak Fusion Result")
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Source Designs")
                .font(.manrope(12, weight: .bold))
                .foregroundStyle(Palette.muted)
                .textCase(.uppercase)

            HStack(spacing: Spacing.md) {
                sourceThumbnail(
                    title: "Design 1 (Strengths)",
                    urlStr: vm.currentGeneration?.sourceImage1URL ?? vm.selectedDesign1?.imageURL,
                    badgeColor: Color(hex: 0xD4AF37)
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.muted)

                sourceThumbnail(
                    title: "Design 2 (Upgrades)",
                    urlStr: vm.currentGeneration?.sourceImage2URL ?? vm.selectedDesign2?.imageURL,
                    badgeColor: Color(hex: 0x3B82F6)
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

    private func sourceThumbnail(title: String, urlStr: String?, badgeColor: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            if let urlStr, let url = URL(string: urlStr) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color(hex: 0xF3F4F6)
                }
                .frame(width: 50, height: 50)
                .clipShape(.rect(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(badgeColor)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Fused Result Card

    private var fusedResultCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Fused Design 3")
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
                if let url = vm.signedOutputImageURL {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Color(hex: 0xF9FAFB)
                            .frame(height: 320)
                            .overlay(ProgressView())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 280)
                    .clipShape(.rect(cornerRadius: 12))
                } else {
                    Color(hex: 0xF9FAFB)
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
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

            Text("This fused output lives in your Chamak Gallery and is not published to your public catalogue.")
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

    // MARK: - Prompt Info Card

    private var promptInfoCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
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

            if let prompt = vm.currentGeneration?.compiledPromptText, !prompt.isEmpty {
                Text(prompt)
                    .font(.manrope(12))
                    .foregroundStyle(Palette.dark.opacity(0.8))
                    .lineLimit(4)
            }
        }
        .padding(Spacing.base)
        .background(Color(hex: 0xF9FAFB), in: .rect(cornerRadius: 10))
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
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Spacing.md) {
                Button {
                    vm.isShowingFeedbackSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.fill")
                        Text(vm.feedbackSubmitted ? "Feedback Sent" : "Feedback")
                    }
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(hex: 0xF3F4F6), in: .rect(cornerRadius: 10))
                }

                Spacer()

                Button {
                    Task {
                        await vm.regenerate(wholesalerID: wholesalerID)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Regenerate")
                    }
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        vm.isQuotaExhausted ? Color(hex: 0x9CA3AF) : Color(hex: 0x111827),
                        in: .rect(cornerRadius: 10)
                    )
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.md)
            .background(Color.white)
        }
    }
}
