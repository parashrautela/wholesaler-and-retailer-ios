import SwiftUI
import PhotosUI

public struct CreateManufacturingRequestSheet: View {
    @Environment(\.dismiss) private var dismiss

    var initialImage: UIImage?
    var initialCategory: String?
    var onCreated: ((UUID) -> Void)?

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var category: String = "Ring"
    @State private var isRangeWeight: Bool = true
    @State private var minWeightText: String = "10.0"
    @State private var maxWeightText: String = "15.0"
    @State private var singleWeightText: String = "12.0"
    @State private var material: String = "Gold"
    @State private var purity: String = "22kt"
    @State private var gemstonePreference: String = "None"
    @State private var quantity: Int = 1
    @State private var budgetMode: MakingBudgetMode = .perGram
    @State private var budgetAmountText: String = "450"
    @State private var deliveryDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var notes: String = ""
    @State private var quotationWindowHours: Int = 24

    @State private var isReviewing: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @State private var submissionIdempotencyKey: String = UUID().uuidString
    @State private var uploadedAssetID: UUID?
    @State private var lastSubmissionPayload: Data?
    #if DEBUG && targetEnvironment(simulator)
    @State private var didRunSimulatorSubmission = false
    #endif

    private let categories = [
        "Ring", "Necklace", "Earrings", "Bangles", "Bracelet", "Pendant", "Haram", "Chain", "Mangalsutra", "Other"
    ]
    private let materials = ["Gold", "Diamond", "Polki", "Kundan", "Platinum", "Silver"]
    private let purities = ["22kt", "18kt", "14kt", "24kt", "925 Silver"]
    private let gemstoneOptions = ["None", "Diamond", "Ruby", "Emerald", "Sapphire", "Polki", "Unspecified"]

    public init(
        initialImage: UIImage? = nil,
        initialCategory: String? = nil,
        onCreated: ((UUID) -> Void)? = nil
    ) {
        self.initialImage = initialImage
        self.initialCategory = initialCategory
        self.onCreated = onCreated
        _selectedImage = State(initialValue: initialImage)
        if let cat = initialCategory, !cat.isEmpty {
            _category = State(initialValue: cat)
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Palette.cream.ignoresSafeArea()

                if isReviewing {
                    reviewView
                } else {
                    formView
                }

                if isSubmitting {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: Spacing.md) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.3)
                        Text("Broadcasting enquiry…")
                            .font(.manrope(15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(Spacing.xl)
                    .background(Palette.dark.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle(isReviewing ? "Review Enquiry" : "Request Custom Jewellery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isReviewing ? "Back" : "Cancel") {
                        if isReviewing {
                            isReviewing = false
                        } else {
                            dismiss()
                        }
                    }
                    .font(.manrope(15, weight: .regular))
                    .foregroundStyle(Palette.dark)
                }

                if !isReviewing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Review") {
                            validateAndProceed()
                        }
                        .font(.manrope(15, weight: .semibold))
                        .foregroundStyle(Palette.dark)
                    }
                }
            }
            .alert("Check Details", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            #if DEBUG && targetEnvironment(simulator)
            .task {
                let fixture = ProcessInfo.processInfo.environment
                guard !didRunSimulatorSubmission,
                      fixture["JEWEL_MFG_TEST_URL"] == "http://127.0.0.1:8810",
                      fixture["JEWEL_MFG_TEST_AUTOSUBMIT"] == "1" else { return }
                didRunSimulatorSubmission = true
                validateAndProceed()
                if isReviewing { await submitRequest() }
            }
            #endif
        }
    }

    // MARK: - Form View

    private var formView: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                imagePickerSection
                categorySection
                weightSection
                specificationsSection
                budgetSection
                deliverySection
                VStack(alignment: .leading) {
                    Text("Time for Wholesalers to Quote")
                        .font(.manrope(13, weight: .semibold))
                    Picker("Quotation Window", selection: $quotationWindowHours) {
                        ForEach([1, 6, 24, 48], id: \.self) { hours in
                            Text("\(hours) hours").tag(hours)
                        }
                    }.pickerStyle(.segmented)
                    Text("All verified wholesalers receive the enquiry together. You choose the supplier from their quotes.")
                        .font(.manrope(12, weight: .regular)).foregroundStyle(Palette.muted)
                }
                notesSection
            }
            .padding(Spacing.base)
        }
    }

    private var imagePickerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Reference Photo")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                if let selectedImage {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Label("Change", systemImage: "photo.badge.plus")
                            .font(.manrope(12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(8)
                    }
                } else {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Palette.muted)
                        Text("Add reference design photo")
                            .font(.manrope(14, weight: .medium))
                            .foregroundStyle(Palette.dark)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                            .foregroundStyle(Palette.border)
                    )
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        selectedImage = uiImage
                        uploadedAssetID = nil
                        lastSubmissionPayload = nil
                        submissionIdempotencyKey = UUID().uuidString
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Category")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        Button {
                            category = cat
                        } label: {
                            Text(cat)
                                .font(.manrope(13, weight: category == cat ? .semibold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(category == cat ? Palette.dark : Color.white)
                                .foregroundStyle(category == cat ? .white : Palette.dark)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Palette.border, lineWidth: category == cat ? 0 : 1))
                        }
                    }
                }
            }
        }
    }

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Expected Weight")
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                Spacer()
                Picker("Weight Mode", selection: $isRangeWeight) {
                    Text("Range").tag(true)
                    Text("Single").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if isRangeWeight {
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Min (grams)").font(.manrope(11, weight: .regular)).foregroundStyle(Palette.muted)
                        TextField("Min", text: $minWeightText)
                            .keyboardType(.decimalPad)
                            .padding(10)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text("to").font(.manrope(14, weight: .medium)).foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Max (grams)").font(.manrope(11, weight: .regular)).foregroundStyle(Palette.muted)
                        TextField("Max", text: $maxWeightText)
                            .keyboardType(.decimalPad)
                            .padding(10)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else {
                TextField("Approx weight (grams)", text: $singleWeightText)
                    .keyboardType(.decimalPad)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var specificationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Material").font(.manrope(13, weight: .semibold)).foregroundStyle(Palette.dark)
                    Picker("Material", selection: $material) {
                        ForEach(materials, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Purity").font(.manrope(13, weight: .semibold)).foregroundStyle(Palette.dark)
                    Picker("Purity", selection: $purity) {
                        ForEach(purities, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Gemstones").font(.manrope(13, weight: .semibold)).foregroundStyle(Palette.dark)
                    Picker("Gemstones", selection: $gemstonePreference) {
                        ForEach(gemstoneOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Quantity").font(.manrope(13, weight: .semibold)).foregroundStyle(Palette.dark)
                    Stepper("\(quantity) pc", value: $quantity, in: 1...500)
                        .padding(8)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Making Charge Budget")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)

            HStack(spacing: Spacing.md) {
                Picker("Mode", selection: $budgetMode) {
                    ForEach(MakingBudgetMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text(budgetMode == .perGram ? "₹/g" : (budgetMode == .fixedTotal ? "₹" : "%"))
                        .font(.manrope(14, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    TextField("Budget", text: $budgetAmountText)
                        .keyboardType(.decimalPad)
                }
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Delivery Needed By")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)

            DatePicker(
                "Target Date",
                selection: $deliveryDate,
                in: (Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())...,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .padding(10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Design Notes (Optional)")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)

            TextField("Specific size, finish, stone placement, or details…", text: $notes, axis: .vertical)
                .lineLimit(3...5)
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Review View

    private var reviewView: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(spacing: 12) {
                    summaryRow(label: "Category", value: category)
                    summaryRow(
                        label: "Weight",
                        value: isRangeWeight ? "\(minWeightText) - \(maxWeightText) g" : "\(singleWeightText) g"
                    )
                    summaryRow(label: "Material & Purity", value: "\(material) (\(purity))")
                    summaryRow(label: "Gemstone Preference", value: gemstonePreference)
                    summaryRow(label: "Quantity", value: "\(quantity) piece(s)")
                    summaryRow(label: "Quotation Window", value: "\(quotationWindowHours) hours")
                    summaryRow(
                        label: "Making Charge Budget",
                        value: budgetMode == .perGram ? "₹\(budgetAmountText) / gram" : (budgetMode == .fixedTotal ? "₹\(budgetAmountText) total" : "\(budgetAmountText)%")
                    )
                    summaryRow(
                        label: "Delivery Deadline",
                        value: deliveryDate.formatted(date: .abbreviated, time: .omitted)
                    )
                    if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        summaryRow(label: "Design Notes", value: notes)
                    }
                }
                .padding(Spacing.base)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text("How Supplier Quotes Work")
                        .font(.manrope(13, weight: .semibold))
                        .foregroundStyle(Palette.dark)
                    Text("All verified wholesalers receive your enquiry at the same time. They submit quotes before the shared deadline. Compare the making charges, estimates and delivery dates, then select your preferred supplier. Submitting a quote does not reserve the project.")
                        .font(.manrope(12, weight: .regular))
                        .foregroundStyle(Palette.muted)
                }
                .padding(Spacing.base)
                .background(Palette.taupe.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    Task { await submitRequest() }
                } label: {
                    Text("Broadcast Request to Wholesalers")
                        .font(.manrope(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.dark)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSubmitting)
            }
            .padding(Spacing.base)
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.manrope(13, weight: .regular))
                .foregroundStyle(Palette.muted)
            Spacer()
            Text(value)
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Actions

    private func validateAndProceed() {
        guard selectedImage != nil else {
            errorMessage = "Please attach a reference photo of the jewellery."
            return
        }

        let minW = isRangeWeight ? (Double(minWeightText) ?? 0) : (Double(singleWeightText) ?? 0)
        let maxW = isRangeWeight ? (Double(maxWeightText) ?? 0) : minW

        guard minW > 0, maxW >= minW else {
            errorMessage = "Please enter a valid weight in grams."
            return
        }

        guard let budget = Double(budgetAmountText), budget > 0 else {
            errorMessage = "Please enter a valid making charge budget."
            return
        }

        isReviewing = true
    }

    private func submitRequest() async {
        guard let selectedImage else { return }
        isSubmitting = true
        errorMessage = nil

        do {
            guard let jpegData = selectedImage.jpegData(compressionQuality: 0.90) else {
                throw ManufacturingAPI.ManufacturingError("Could not process reference photo.")
            }

            // 1. Upload asset
            let assetID: UUID
            if let uploadedAssetID {
                assetID = uploadedAssetID
            } else {
                let uploadRes = try await ManufacturingAPI.uploadAsset(imageData: jpegData)
                guard uploadRes.ok else {
                    throw ManufacturingAPI.ManufacturingError("The reference photo could not be saved. Please retry.")
                }
                assetID = uploadRes.assetID
                uploadedAssetID = assetID
            }

            let minW = isRangeWeight ? (Double(minWeightText) ?? 0) : (Double(singleWeightText) ?? 0)
            let maxW = isRangeWeight ? (Double(maxWeightText) ?? 0) : minW
            let budget = Double(budgetAmountText) ?? 0

            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let dateStr = formatter.string(from: deliveryDate)

            // 2. Submit request with idempotency key
            let params = CreateManufacturingRequestParams(
                assetId: assetID,
                category: category,
                minWeightGrams: minW,
                maxWeightGrams: maxW,
                material: material,
                purity: purity,
                gemstonePreference: gemstonePreference,
                quantity: quantity,
                makingBudgetMode: budgetMode.rawValue,
                makingBudgetAmount: budget,
                currency: "INR",
                metalRateSnapshot: nil,
                metalRateBasis: nil,
                deliveryNeededDate: dateStr,
                notes: notes.isEmpty ? nil : notes,
                supersededRequestId: nil,
                quotationWindowHours: quotationWindowHours
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let submissionPayload = try encoder.encode(params)
            if let previous = lastSubmissionPayload, previous != submissionPayload {
                submissionIdempotencyKey = UUID().uuidString
            }
            lastSubmissionPayload = submissionPayload

            let res = try await ManufacturingAPI.createRequest(
                params: params,
                idempotencyKey: submissionIdempotencyKey
            )

            guard res.ok, let reqID = res.requestID else {
                throw ManufacturingAPI.ManufacturingError("The server did not confirm your enquiry. Please retry.")
            }
            isSubmitting = false
            onCreated?(reqID)
            dismiss()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
        }
    }
}
