import PhotosUI
import SwiftUI

/// Adds one of the store's own pieces to its catalogue.
///
/// Unlike a wholesaler's Add Product, this never touches the AI pipeline: the
/// photos are sized down here on the device, uploaded as they are, and the
/// design is in the catalogue as soon as Save returns.
struct AddDesignSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    var onAdded: () -> Void

    private static let maxPhotos = 4
    /// Long edge, in pixels. Plenty for a full-screen phone or iPad view, and
    /// a fraction of a camera original's size.
    private static let maxPixels: CGFloat = 1800

    @State private var picked: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []
    @State private var isReadingPhotos = false

    @State private var title = ""
    @State private var type = ""
    @State private var category = ""
    @State private var style = ""
    @State private var purity = ""
    @State private var netWeight = ""
    @State private var inStock = true
    @State private var productionDays = ""

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !photos.isEmpty && !title.trimmed.isEmpty && !type.isEmpty && !isSaving && !isReadingPhotos
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    photoStrip
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Up to \(Self.maxPhotos). The first is the cover. Photos are added as they are.")
                }

                Section("Design") {
                    TextField("Name", text: $title)
                    picker("Type", selection: $type, options: AddProductForm.types, required: true)
                    picker("Category", selection: $category, options: AddProductForm.categories)
                    picker("Style", selection: $style, options: AddProductForm.styles)
                }

                Section("Details") {
                    picker("Purity", selection: $purity, options: AddProductForm.purities)
                    HStack {
                        Text("Net weight")
                        Spacer()
                        TextField("0.00", text: $netWeight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("g").foregroundStyle(Palette.muted)
                    }
                    Toggle("In stock", isOn: $inStock)
                    if !inStock {
                        HStack {
                            Text("Made to order in")
                            Spacer()
                            TextField("0", text: $productionDays)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 60)
                            Text("days").foregroundStyle(Palette.muted)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(Color.red)
                    }
                }
            }
            .navigationTitle("Add Design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onChange(of: picked) { _, items in
                Task { await read(items) }
            }
        }
    }

    private var photoStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                photos.remove(at: index)
                                if index < picked.count { picked.remove(at: index) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .padding(4)
                            .accessibilityLabel("Remove photo \(index + 1)")
                        }
                }

                if photos.count < Self.maxPhotos {
                    PhotosPicker(selection: $picked, maxSelectionCount: Self.maxPhotos, matching: .images) {
                        VStack(spacing: 6) {
                            if isReadingPhotos {
                                ProgressView()
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 22))
                                Text(photos.isEmpty ? "Add Photos" : "Add More")
                                    .font(.manrope(11, weight: .semibold))
                            }
                        }
                        .foregroundStyle(Palette.dark)
                        .frame(width: 84, height: 84)
                        .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isReadingPhotos)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func picker(_ label: String, selection: Binding<String>,
                        options: [AddProductForm.Option], required: Bool = false) -> some View {
        Picker(label, selection: selection) {
            Text(required ? "Choose" : "None").tag("")
            ForEach(options) { option in
                Text(option.label).tag(option.value)
            }
        }
    }

    private func read(_ items: [PhotosPickerItem]) async {
        isReadingPhotos = true
        defer { isReadingPhotos = false }
        var loaded: [UIImage] = []
        for item in items.prefix(Self.maxPhotos) {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        photos = loaded
        if loaded.count < items.count {
            errorMessage = "Some photos couldn't be read and were skipped."
        } else {
            errorMessage = nil
        }
    }

    private func save() async {
        guard canSave, let user = session.user else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let encoded = photos.compactMap { Self.jpeg($0) }
        guard !encoded.isEmpty else {
            errorMessage = "These photos couldn't be prepared. Try different ones."
            return
        }

        do {
            try await RetailerAPI.addDesign(
                RetailerAPI.NewDesign(
                    title: title.trimmed,
                    type: type.nilIfEmpty,
                    category: category.nilIfEmpty,
                    style: style.nilIfEmpty,
                    purity: purity.nilIfEmpty,
                    netWeight: Double(netWeight.replacingOccurrences(of: ",", with: ".")),
                    inStock: inStock,
                    productionDays: Int(productionDays)
                ),
                photos: encoded,
                userID: user.id
            )
            onAdded()
            dismiss()
        } catch {
            errorMessage = "Couldn't save this design. Check your connection and try again."
        }
    }

    /// Sized to `maxPixels` on the long edge and re-encoded, which also bakes
    /// in the photo's orientation.
    private static func jpeg(_ image: UIImage) -> Data? {
        let longEdge = max(image.size.width, image.size.height) * image.scale
        let ratio = min(1, maxPixels / max(longEdge, 1))
        let target = CGSize(width: image.size.width * image.scale * ratio,
                            height: image.size.height * image.scale * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
