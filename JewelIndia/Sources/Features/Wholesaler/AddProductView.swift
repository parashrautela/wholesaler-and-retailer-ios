import PhotosUI
import SwiftUI

/// `/dashboard/wholesaler/add-product` — the AI upload flow.
///
/// Three numbered sections (image, essential details, specifications), a daily
/// upload-limit banner, full on-submit validation, and a status machine that
/// replaces the whole form while the pipeline runs.
///
/// Note the web performs **no polling and shows no AI progress here** — the
/// user is told results arrive within 24 hours. `ProcessingView` exists in the
/// codebase but is wired to nothing. That is reproduced, not "improved".
struct AddProductView: View {
    @Environment(SessionStore.self) private var session

    @State private var form = AddProductForm()
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showSuccess = false

    var body: some View {
        Group {
            if form.status.isBusy {
                statusOverlay
            } else {
                formBody
            }
        }
        .background(Color.white)
        .navigationTitle("Add new product")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // The picker hands back the original asset, which is HEIC
                    // for anything shot on-device. Re-encode to JPEG and bound
                    // the size here, so what is previewed is exactly what is
                    // uploaded — see `ImageNormalizer` for why.
                    if let jpeg = ImageNormalizer.jpeg(
                        from: data,
                        maxDimension: ImageNormalizer.maxProductDimension
                    ) {
                        form.image = PickedFile(
                            data: jpeg, filename: "product.jpg", mimeType: "image/jpeg"
                        )
                        form.errors.removeValue(forKey: "image")
                    } else {
                        form.errors["image"] = "That file couldn't be read as an image. Try another photo."
                    }
                }
                photoItem = nil
            }
        }
        .task { await form.loadUsage(session: session) }
        .navigationDestination(isPresented: $showSuccess) {
            AddProductSuccessView()
        }
    }

    // MARK: - Status overlay

    /// While `uploading | saving | done` the entire form is replaced.
    private var statusOverlay: some View {
        VStack(spacing: Spacing.xl) {
            SpinnerRing()
            Text(form.status.caption)
                .font(.gilroy(14))
                .tracking(14 * 0.1)
                .textCase(.uppercase)
                .foregroundStyle(Color(hex: 0x6B7280))
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .transition(.opacity)
    }

    // MARK: - Form

    /// The web caps this page at `md:max-w-[640px]` / `lg:max-w-[880px]` and
    /// centers it (`mx-auto`) — the fixed `Spacing.base` (16pt) padding this
    /// used before applied on every screen size, so on anything iPad-width or
    /// wider the form stretched edge to edge instead of sitting in a centered
    /// column with real margins either side.
    private var formBody: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let isLarge = width >= Breakpoint.lg
            let isMedium = width >= Breakpoint.md
            let maxContentWidth: CGFloat = isLarge ? 880 : (isMedium ? 640 : .infinity)
            let gutter: CGFloat = isLarge ? 40 : (isMedium ? 32 : Spacing.base)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    usageBanner

                    if let banner = form.bannerError {
                        ErrorBanner(message: banner)
                    }

                    imageSection
                    detailsSection
                    specificationsSection
                    submitArea
                    footer
                }
                .padding(.horizontal, gutter)
                .padding(.vertical, Spacing.xl)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add new product")
                .font(.cirka(28, weight: .semibold))
                .foregroundStyle(Color(hex: 0x111827))
            Text("Enter the details below to create a sparkling new listing.")
                .font(.gilroy(16, weight: .medium))
                .foregroundStyle(Color(hex: 0x6B7280))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Usage banner

    @ViewBuilder
    private var usageBanner: some View {
        if form.usageLoading {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: 0xF9FAFB))
                .frame(height: 62)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: 0xF3F4F6), lineWidth: 1)
                }
                .shimmering()
        } else if form.usage.isUnlimited {
            // `limit` falsy / Infinity → no banner at all.
            EmptyView()
        } else if form.isLimitReached {
            limitReachedBanner
        } else {
            progressBanner
        }
    }

    private var limitReachedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("⚠️").font(.system(size: 18))
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily upload limit reached")
                    .font(.gilroy(14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x856404))
                Text(form.limitReachedMessage)
                    .font(.gilroy(13))
                    .foregroundStyle(Color(hex: 0x856404))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("\(form.usage.used) / \(form.usage.limit ?? 0) Used")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0x856404))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(hex: 0xFBEFBE).opacity(0.6), in: .capsule)
        }
        .padding(Spacing.base)
        .background(Color(hex: 0xFFFDF5), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xFBEFBE), lineWidth: 1)
        }
        .transition(.opacity)
    }

    private var progressBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Daily Upload Progress")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x374151))
                Spacer()
                Text("\(form.usage.used) / \(form.usage.limit ?? 0) uploads used today")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x6B7280))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xF3F4F6))
                    Capsule().fill(.black)
                        .frame(width: proxy.size.width * form.usageFraction)
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.5), value: form.usageFraction)
        }
        .padding(Spacing.base)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE5E5E5), lineWidth: 1)
        }
    }

    // MARK: - Section 1

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                number: 1,
                title: "Product image",
                subtitle: "Upload a clear image. We'll remove the background first, then enhance it."
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Get the best result from your photo:")
                    .font(.gilroy(14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x374151))
                ForEach(Array(AddProductForm.photoTips.enumerated()), id: \.offset) { index, tip in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.gilroy(13))
                            .foregroundStyle(Color(hex: 0x6B7280))
                        Text(tip)
                            .font(.gilroy(13))
                            .foregroundStyle(Color(hex: 0x6B7280))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            dropzone

            if let error = form.errors["image"] {
                Text(error)
                    .font(.gilroy(12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xEF4444))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dropzone: some View {
        VStack(spacing: Spacing.md) {
            Color.clear
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let image = form.image?.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(Spacing.base)
                    } else {
                        Circle()
                            .strokeBorder(
                                Color(hex: 0x3B82F6),
                                style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                            )
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(Color(hex: 0x3B82F6))
                            }
                    }
                }
                .background(
                    form.errors["image"] != nil ? Color(hex: 0xFEF2F2) : Color(hex: 0xF1F5F9),
                    in: .rect(cornerRadius: 10)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            form.errors["image"] != nil ? Color(hex: 0xEF4444) : Color(hex: 0x3B82F6),
                            style: StrokeStyle(lineWidth: 2, dash: [7, 6])
                        )
                }
                .contentShape(.rect)
                .onTapGesture {
                    guard form.image == nil else { return }
                    showPhotoPicker = true
                }

            if form.image != nil {
                HStack(spacing: Spacing.base) {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                            Text("Change Image").font(.gilroy(14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black, in: .rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        form.image = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash").font(.system(size: 14))
                            Text("Remove").font(.gilroy(14, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: 0xEF4444))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Section 2

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            SectionHeader(
                number: 2,
                title: "Essential details",
                // "peice" is the source's typo, preserved.
                subtitle: "Add the key information that helps retailers understand and find this peice."
            )

            LabelledField(label: "Product Title", error: form.errors["title"]) {
                TextField("eg. Vintage gold Necklace", text: $form.title)
                    .fieldChrome(hasError: form.errors["title"] != nil)
                    .onChange(of: form.title) { _, _ in form.errors.removeValue(forKey: "title") }
            }

            JewelSelect(
                label: "Type",
                options: AddProductForm.types,
                selection: $form.jewelleryType,
                error: form.errors["jewellery_type"]
            )
            JewelSelect(
                label: "Material Category",
                options: AddProductForm.categories,
                selection: $form.category,
                error: form.errors["category"]
            )
            JewelSelect(
                label: "Style Aesthetic",
                options: AddProductForm.styles,
                selection: $form.style,
                error: form.errors["style"]
            )
            JewelSelect(
                label: "Size",
                options: AddProductForm.sizes,
                selection: $form.size,
                error: form.errors["size"]
            )
            JewelSelect(
                label: "Purity",
                options: AddProductForm.purities,
                selection: $form.metalPurity,
                error: form.errors["metalPurity"]
            )
        }
    }

    // MARK: - Section 3

    private var specificationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            SectionHeader(
                number: 3,
                title: "Specifications",
                subtitle: "Add weight and stone details so retailers know exactly what they're getting."
            )

            InputWithSuffix(
                label: "Gross Weight", suffix: "g",
                text: $form.grossWeight, error: form.errors["grossWeight"]
            )
            InputWithSuffix(
                label: "Stone Weight", suffix: "g",
                text: $form.stoneWeight, error: form.errors["stoneWeight"]
            )
            InputWithSuffix(
                label: "Net Weight", suffix: "g",
                text: $form.netWeight, error: form.errors["netWeight"]
            )

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Available in Stock")
                        .font(.gilroy(14, weight: .bold))
                        .foregroundStyle(Color(hex: 0x111827))
                    Text("Is this piece ready to shift right away?")
                        .font(.gilroy(13))
                        .foregroundStyle(Color(hex: 0x6B7280))
                }
                Spacer()
                JewelToggle(isOn: $form.stockAvailable)
            }
            .padding(.vertical, Spacing.base)
            .onChange(of: form.stockAvailable) { _, isOn in
                if isOn { form.errors.removeValue(forKey: "makeToOrderDays") }
            }

            if !form.stockAvailable {
                InputWithSuffix(
                    label: "Production time", suffix: "days", placeholder: "eg. 14",
                    text: $form.makeToOrderDays, error: form.errors["makeToOrderDays"]
                )
                .transition(.opacity)
            }
        }
        .animation(Motion.fadeIn, value: form.stockAvailable)
    }

    // MARK: - Submit

    private var submitArea: some View {
        VStack(spacing: Spacing.md) {
            Button {
                Task { await submit(publish: true) }
            } label: {
                Text("Submit")
                    .font(.gilroy(16, weight: .semibold))
                    .foregroundStyle(form.isLimitReached ? Color(hex: 0x6B7280) : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        form.isLimitReached ? Color(hex: 0xD1D5DB) : .black,
                        in: .capsule
                    )
            }
            .buttonStyle(.plain)
            .disabled(form.isLimitReached)

            // Never disabled, even at the daily limit — matches the web.
            Button {
                Task { await submit(publish: false) }
            } label: {
                Text("Save & Upload Later")
                    .font(.gilroy(16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white, in: .capsule)
                    .overlay { Capsule().stroke(.black, lineWidth: 1) }
            }
            .buttonStyle(.plain)

            Text("*By submitting, you allow us to display your product details and\nimages to retailers on the platform.")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Spacing.sm)
    }

    private var footer: some View {
        HStack {
            Text("All Rights Reserved © Jewels India")
                .font(.gilroy(13))
                .foregroundStyle(Color(hex: 0x6B7280))
            Spacer()
            Text("Crafted with ❤️ in blr")
                .font(.gilroy(13))
                .foregroundStyle(Color(hex: 0x374151))
        }
        .padding(.top, Spacing.xl)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(hex: 0xE5E5E5)).frame(height: 1)
        }
    }

    private func submit(publish: Bool) async {
        guard let user = session.user else { return }
        if await form.submit(user: user, publish: publish) {
            if publish { showSuccess = true }
        }
    }
}

// MARK: - Success

/// `/dashboard/wholesaler/add-product/success`.
struct AddProductSuccessView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Submitted")
                .font(.custom("Georgia", size: 44))
                .foregroundStyle(.black)
                .padding(.bottom, Spacing.xl)

            Text("Your design is in good hands. We've received your photo and details. Our AI is getting to work you'll see your studio-ready images within 24 hours.")
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: 0x6B6B6B))
                .lineSpacing(16 * 0.6)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.bottom, Spacing.xxl)

            Button {
                dismiss()
            } label: {
                Text("Back to dashboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 18)
                    .background(Color(hex: 0x0A0A0A), in: .rect(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.base)
        .background(Color.white)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }
}
