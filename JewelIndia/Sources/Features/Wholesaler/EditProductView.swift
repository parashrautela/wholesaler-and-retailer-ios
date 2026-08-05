import SwiftUI

/// Edit product screen for wholesalers (`/dashboard/wholesaler/edit-product/[id]`).
/// Allows editing product title, categories, purity, weights, stock availability,
/// and publication flags.
struct EditProductView: View {
    @Environment(\.dismiss) private var dismiss
    
    let product: Product
    var onSaved: (Product) -> Void

    @State private var title: String
    @State private var jewelleryType: String
    @State private var category: String
    @State private var style: String
    @State private var size: String
    @State private var metalPurity: String
    @State private var grossWeight: String
    @State private var stoneWeight: String
    @State private var netWeight: String
    @State private var stockAvailable: Bool
    @State private var makeToOrderDays: String
    @State private var isPublished: Bool

    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    init(product: Product, onSaved: @escaping (Product) -> Void) {
        self.product = product
        self.onSaved = onSaved
        
        _title = State(initialValue: product.title ?? "")
        _jewelleryType = State(initialValue: product.jewelleryType ?? "")
        _category = State(initialValue: product.category ?? "")
        _style = State(initialValue: product.style ?? "")
        _size = State(initialValue: product.size ?? "")
        _metalPurity = State(initialValue: product.metalPurity ?? "")
        _grossWeight = State(initialValue: product.grossWeight.map { String($0) } ?? "")
        _stoneWeight = State(initialValue: product.stoneWeight.map { String($0) } ?? "")
        _netWeight = State(initialValue: product.netWeight.map { String($0) } ?? "")
        _stockAvailable = State(initialValue: product.stockAvailable ?? true)
        _makeToOrderDays = State(initialValue: product.makeToOrderDays.map { String($0) } ?? "")
        _isPublished = State(initialValue: product.isPublished ?? true)
    }

    var body: some View {
        Form {
            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.manrope(13, weight: .medium))
                        .foregroundStyle(Color.red)
                }
            }

            Section("Product Info") {
                TextField("Product Title", text: $title)
                    .font(.manrope(14))

                Picker("Category", selection: $category) {
                    Text("Select Category").tag("")
                    ForEach(CatalogueCategory.all) { cat in
                        Text(cat.name).tag(cat.slug)
                    }
                }

                Picker("Purity", selection: $metalPurity) {
                    Text("Select Purity").tag("")
                    Text("24K (999)").tag("24k")
                    Text("22K (916)").tag("22k")
                    Text("18K (750)").tag("18k")
                    Text("14K (585)").tag("14k")
                    Text("925 Silver").tag("925")
                    Text("950 Platinum").tag("950pt")
                }
            }

            Section("Specifications") {
                HStack {
                    Text("Gross Weight (g)")
                    Spacer()
                    TextField("0.00", text: $grossWeight)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Stone Weight (g)")
                    Spacer()
                    TextField("0.00", text: $stoneWeight)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Net Weight (g)")
                    Spacer()
                    TextField("0.00", text: $netWeight)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Availability") {
                Toggle("In Stock", isOn: $stockAvailable)

                if !stockAvailable {
                    HStack {
                        Text("Production Time (days)")
                        Spacer()
                        TextField("14", text: $makeToOrderDays)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Toggle("Published to Catalogue", isOn: $isPublished)
            }
        }
        .navigationTitle("Edit Product")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await saveChanges() }
                }
                .disabled(isSaving)
            }
        }
    }

    private func saveChanges() async {
        isSaving = true
        errorMessage = nil
        
        let edit = WholesalerAPI.ProductEdit(
            title: title.trimmed,
            category: category.trimmed.isEmpty ? nil : category,
            style: style.trimmed.isEmpty ? nil : style,
            size: size.trimmed.isEmpty ? nil : size,
            metal_purity: metalPurity.trimmed.isEmpty ? nil : metalPurity,
            net_weight: Double(netWeight),
            gross_weight: Double(grossWeight),
            stone_weight: Double(stoneWeight),
            stock_available: stockAvailable,
            make_to_order_days: Int(makeToOrderDays),
            is_published: isPublished
        )

        do {
            try await WholesalerAPI.updateProduct(id: product.id, edit: edit)
            let updatedProduct = Product(
                id: product.id,
                wholesalerId: product.wholesalerId,
                wholesalerEmail: product.wholesalerEmail,
                title: title.trimmed,
                jewelleryType: jewelleryType,
                category: category,
                style: style,
                size: size,
                stockAvailable: stockAvailable,
                makeToOrderDays: Int(makeToOrderDays),
                metalPurity: metalPurity,
                netWeight: Double(netWeight),
                grossWeight: Double(grossWeight),
                stoneWeight: Double(stoneWeight),
                rawImageURL: product.rawImageURL,
                processedImageURL: product.processedImageURL,
                isPublished: isPublished,
                createdAt: product.createdAt
            )
            onSaved(updatedProduct)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
