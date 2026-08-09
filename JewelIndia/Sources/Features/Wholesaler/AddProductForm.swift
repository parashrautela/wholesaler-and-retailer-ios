import Observation
import Supabase
import SwiftUI

/// State + submit pipeline for the add-product screen.
@MainActor
@Observable
final class AddProductForm {

    enum Status: Equatable {
        case idle, uploading, saving, done, error

        var isBusy: Bool { self == .uploading || self == .saving || self == .done }

        var caption: String {
            switch self {
            case .uploading: "Uploading Image..."
            case .saving: "Saving metadata..."
            case .done: "Redirecting..."
            default: ""
            }
        }
    }

    // Fields
    var image: PickedFile?
    var title = ""
    var jewelleryType = ""
    var category = ""
    var style = ""
    var size = ""
    var metalPurity = ""
    var grossWeight = ""
    var stoneWeight = ""
    var netWeight = ""
    var stockAvailable = true
    var makeToOrderDays = ""

    var errors: [String: String] = [:]
    var bannerError: String?
    var status: Status = .idle

    var usage: UploadUsage = .unknown
    var usageLoading = true

    var isLimitReached: Bool {
        guard let limit = usage.limit else { return false }
        return usage.used >= limit
    }

    var usageFraction: CGFloat {
        guard let limit = usage.limit, limit > 0 else { return 0 }
        return min(1, CGFloat(usage.used) / CGFloat(limit))
    }

    var limitReachedMessage: String {
        var text = "You have used all \(usage.limit ?? 0) uploads for today."
        if let resets = usage.resetsAt, let date = Self.parseResetDate(resets) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            text += " Resets at \(formatter.string(from: date))."
        }
        return text
    }

    /// The API returns `…+00:00Z` / `…+00:00`, which the web sanitises to `Z`
    /// before parsing.
    private static func parseResetDate(_ raw: String) -> Date? {
        let cleaned = raw
            .replacingOccurrences(of: "+00:00Z", with: "Z")
            .replacingOccurrences(of: "+00:00", with: "Z")
        return ISO8601DateFormatter.jewel.date(from: cleaned)
            ?? ISO8601DateFormatter().date(from: cleaned)
    }

    static let photoTips = [
        "Place the jewellery on a background that contrasts with the product.",
        "Upload a clear well-lit photo.",
        "Keep only the product in the frame",
    ]

    // MARK: - Select options (value → label, exact order)

    struct Option: Identifiable, Hashable {
        let value: String
        let label: String
        var id: String { value }
    }

    static let types = [
        Option(value: "necklace", label: "Necklace"), Option(value: "rings", label: "Rings"),
        Option(value: "earrings", label: "Earrings"), Option(value: "haram", label: "Haram"),
        Option(value: "pendant", label: "Pendant"), Option(value: "bangles", label: "Bangles"),
        Option(value: "nosepins", label: "Nosepins"), Option(value: "mangalsutra", label: "Mangalsutra"),
    ]
    static let categories = [
        Option(value: "gold", label: "Gold"), Option(value: "silver", label: "Silver"),
        Option(value: "diamond", label: "Diamond"), Option(value: "platinum", label: "Platinum"),
        Option(value: "gemstone", label: "Gemstone"), Option(value: "pearl", label: "Pearl"),
    ]
    static let styles = [
        Option(value: "traditional", label: "Traditional"), Option(value: "modern", label: "Modern"),
        Option(value: "fusion", label: "Fusion"), Option(value: "antique", label: "Antique"),
        Option(value: "minimalist", label: "Minimalist"), Option(value: "bridal", label: "Bridal"),
    ]
    static let sizes = [
        Option(value: "xs", label: "XS"), Option(value: "s", label: "S"),
        Option(value: "m", label: "M"), Option(value: "l", label: "L"),
        Option(value: "xl", label: "XL"), Option(value: "freesize", label: "Free Size"),
    ]
    static let purities = [
        Option(value: "24k", label: "24K (999)"), Option(value: "22k", label: "22K (916)"),
        Option(value: "18k", label: "18K (750)"), Option(value: "14k", label: "14K (585)"),
        Option(value: "925", label: "925 Silver"), Option(value: "950pt", label: "950 Platinum"),
    ]

    // MARK: - Usage

    func loadUsage(session: SessionStore) async {
        guard let user = session.user else { usageLoading = false; return }
        usage = await WholesalerAPI.fetchUploadUsage(wholesalerID: user.id)
        usageLoading = false
    }

    // MARK: - Validation

    /// Runs entirely on submit, in this exact order — the first failing key is
    /// what the web scrolls to.
    func validate(requiresImage: Bool) -> Bool {
        var found: [String: String] = [:]

        if requiresImage, image == nil {
            found["image"] = "Please upload a product image."
        }
        if title.trimmed.isEmpty {
            found["title"] = "Product title is required."
        }
        if jewelleryType.isEmpty { found["jewellery_type"] = "Please select a jewellery type." }
        if category.isEmpty { found["category"] = "Please select a material category." }
        if style.isEmpty { found["style"] = "Please select a style aesthetic." }
        if size.isEmpty { found["size"] = "Please select a size." }
        if metalPurity.isEmpty { found["metalPurity"] = "Please select a purity." }

        if let value = Double(grossWeight), value > 0 {} else {
            found["grossWeight"] = "Gross weight must be greater than 0."
        }
        if stoneWeight.isEmpty || Double(stoneWeight) == nil || (Double(stoneWeight) ?? -1) < 0 {
            found["stoneWeight"] = "Stone weight must be 0 or greater."
        }
        if let value = Double(netWeight), value > 0 {} else {
            found["netWeight"] = "Net weight must be greater than 0."
        }
        if !stockAvailable {
            if let days = Int(makeToOrderDays), days > 0 {} else {
                found["makeToOrderDays"] = "Production time must be greater than 0 days."
            }
        }

        errors = found
        bannerError = found.isEmpty ? nil : "Please correct the fields highlighted in red below."
        return found.isEmpty
    }

    // MARK: - Submit

    /// Path A (`publish == true`) requires an image and posts to the pipeline.
    /// Path B ("Save & Upload Later") allows no image at all, and writes
    /// `is_published: false`.
    func submit(user: User, publish: Bool) async -> Bool {
        let requiresImage = publish
        guard validate(requiresImage: requiresImage) else { return false }

        bannerError = nil

        // Path B with no image skips the pipeline entirely.
        guard image != nil else {
            status = .saving
            do {
                try await insertProductWithoutImage(user: user)
                status = .idle
                return true
            } catch {
                bannerError = error.localizedDescription
                status = .error
                return false
            }
        }

        do {
            status = .uploading
            let titleValue = title.trimmed.isEmpty
                ? (Self.types.first { $0.value == jewelleryType }?.label ?? "Untitled")
                : title.trimmed

            let response = try await WholesalerAPI.processProduct(
                imageData: image!.data,
                filename: image!.filename,
                mimeType: image!.mimeType,
                title: titleValue,
                jewelleryType: jewelleryType,
                wholesalerID: user.id
            )

            status = .saving
            guard let productID = response.productId else {
                throw WholesalerAPI.PipelineError(message: "Upload failed — no product id returned.")
            }
            try await saveProduct(
                productID: productID,
                user: user,
                title: titleValue,
                rawImageURL: response.rawImageURL,
                isPublished: publish ? nil : false
            )

            status = .done
            usage = await WholesalerAPI.fetchUploadUsage(wholesalerID: user.id)
            status = .idle
            return true

        } catch let error as JewelAPI.APIError {
            handle(error.message, status: error.status, user: user)
            return false
        } catch let error as WholesalerAPI.PipelineError {
            bannerError = error.message
            status = .error
            return false
        } catch {
            bannerError = error.localizedDescription
            status = .error
            return false
        }
    }

    private func handle(_ message: String, status code: Int, user: User) {
        // The web maps the pipeline's status codes to fixed copy.
        switch code {
        case 413: bannerError = "File exceeds 10 MB limit."
        case 415: bannerError = "Unsupported file type. Use JPEG, PNG or WebP."
        case 429:
            bannerError = "Daily upload limit reached. Please try again tomorrow."
            Task { usage = await WholesalerAPI.fetchUploadUsage(wholesalerID: user.id) }
        default: bannerError = message
        }
        status = .error
    }

    /// `saveProduct` — the pipeline creates the row, this claims and completes it.
    private func saveProduct(
        productID: String,
        user: User,
        title: String,
        rawImageURL: String?,
        isPublished: Bool?
    ) async throws {
        var payload: [String: AnyJSON] = [
            "wholesaler_id": .string(user.id.uuidString),
            "title": .string(title),
            "jewellery_type": .string(jewelleryType),
            "category": .string(category),
            "style": .string(style),
            "size": .string(size),
            "metal_purity": .string(metalPurity),
            "stock_available": .bool(stockAvailable),
        ]
        if let email = user.email { payload["wholesaler_email"] = .string(email) }
        if let raw = rawImageURL { payload["raw_image_url"] = .string(raw) }
        if let published = isPublished { payload["is_published"] = .bool(published) }
        payload["net_weight"] = Double(netWeight).map { .double($0) } ?? .null
        payload["gross_weight"] = Double(grossWeight).map { .double($0) } ?? .null
        payload["stone_weight"] = Double(stoneWeight).map { .double($0) } ?? .null
        payload["make_to_order_days"] = stockAvailable
            ? .null
            : (Int(makeToOrderDays).map { .integer($0) } ?? .null)

        // The pipeline has already created this row; if the claim is lost the
        // upload is orphaned, so a transport stall must be retried rather than
        // surfaced as a failure.
        let body = payload
        let response = try await JewelNetwork.withRetry {
            try await SupabaseManager.client
                .from("products")
                .update(body)
                .eq("id", value: productID)
                .select("id")
                .execute()
        }

        // The web surfaces a very specific message when RLS silently matches
        // zero rows; reproduced because it is genuinely diagnostic.
        struct IDRow: Decodable { let id: String }
        let rows = (try? JSONDecoder().decode([IDRow].self, from: response.data)) ?? []
        if rows.isEmpty {
            throw WholesalerAPI.PipelineError(
                message: "Save blocked: 0 rows updated. Have you run the RLS hotfix SQL in your Supabase dashboard? See SUPABASE_SETUP.sql Step 0."
            )
        }
    }

    /// `insertProduct` — Path B without an image.
    private func insertProductWithoutImage(user: User) async throws {
        var payload: [String: AnyJSON] = [
            "wholesaler_id": .string(user.id.uuidString),
            "title": .string(title.trimmed.isEmpty ? "Untitled" : title.trimmed),
            "jewellery_type": .string(jewelleryType),
            "category": .string(category),
            "style": .string(style),
            "size": .string(size),
            "metal_purity": .string(metalPurity),
            "stock_available": .bool(stockAvailable),
            "is_published": .bool(false),
        ]
        if let email = user.email { payload["wholesaler_email"] = .string(email) }
        payload["net_weight"] = Double(netWeight).map { .double($0) } ?? .null
        payload["gross_weight"] = Double(grossWeight).map { .double($0) } ?? .null
        payload["stone_weight"] = Double(stoneWeight).map { .double($0) } ?? .null
        payload["make_to_order_days"] = stockAvailable
            ? .null
            : (Int(makeToOrderDays).map { .integer($0) } ?? .null)

        let body = payload
        _ = try await JewelNetwork.withRetry {
            try await SupabaseManager.client.from("products").insert(body).execute()
        }
    }
}
