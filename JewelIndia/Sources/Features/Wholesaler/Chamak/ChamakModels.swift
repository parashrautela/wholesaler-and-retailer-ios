import CryptoKit
import Foundation

// MARK: - Chamak Status

enum ChamakStatus: String, Codable, Sendable {
    case queued
    case analyzing
    case awaitingInput = "awaiting_input"
    case generating
    case done
    case failed

    func displayLabel(mode: ChamakMode = .fusion) -> String {
        switch self {
        case .queued: "Queued"
        case .analyzing: "Analyzing Designs"
        case .awaitingInput: "Awaiting Input"
        case .generating: mode == .setCreation ? "Staging Your Set" : "Fusing Designs"
        case .done: mode == .setCreation ? "Set Complete" : "Fusion Complete"
        case .failed: "Generation Failed"
        }
    }
}

// MARK: - Chamak Mode

/// `fusion` blends two designs of the same category into one new piece.
/// `set_creation` stages two different, real pieces together unchanged, as a
/// matched-set catalogue photo — the inverse operation. Both share the same
/// `chamak_generations` table, polling endpoint, picker UI and credit system;
/// only the styling step and generate endpoint differ. See
/// `CHAMAK_SET_CREATION_SPEC.md` and `ai-pipeline/app/main.py`'s
/// `/api/set-creation/generate` route.
enum ChamakMode: String, Codable, Sendable {
    case fusion
    case setCreation = "set_creation"
}

// MARK: - Set Creation Backdrop

/// The 4 staging presets a wholesaler picks between in Set Creation mode.
/// Copy matches the web app's `SET_BACKDROPS` exactly
/// (`lib/supabase/set-creation-queries.js`) — the longer scene-description
/// prose used to actually build the AI prompt lives server-side only and is
/// never sent to or from the client.
enum SetBackdrop: String, CaseIterable, Codable, Sendable {
    case velvetBust = "velvet_bust"
    case darkSlate = "dark_slate"
    case festive
    case cleanStudio = "clean_studio"

    var label: String {
        switch self {
        case .velvetBust: "Velvet Bust"
        case .darkSlate: "Dark Slate"
        case .festive: "Festive"
        case .cleanStudio: "Clean Studio"
        }
    }

    var blurb: String {
        switch self {
        case .velvetBust: "Teal velvet bust and stands, maroon silk backdrop"
        case .darkSlate: "Charcoal stone surface, dramatic side light"
        case .festive: "Maroon and gold silk, warm bokeh, marigold accents"
        case .cleanStudio: "Seamless light-grey sweep, soft even lighting"
        }
    }
}

// MARK: - Content Flag

enum ContentFlag: String, Codable, Sendable {
    case ok
    case notJewelry = "not_jewelry"
    case inappropriate
    case tooUnclearToAssess = "too_unclear_to_assess"

    var userMessage: String? {
        switch self {
        case .ok:
            return nil
        case .notJewelry:
            return "One or both selected images do not appear to be jewelry. Please select jewelry designs from your catalogue or upload clear jewelry photos."
        case .inappropriate:
            return "Selected images contain inappropriate or unsupported visual content."
        case .tooUnclearToAssess:
            return "One or both images are too blurry or unclear for precision vision analysis."
        }
    }
}

// MARK: - Stage 1 Vision Analysis

struct Stage1Analysis: Codable, Sendable {
    let jewelryType: String
    let image1Strengths: [String]
    let image1Weaknesses: [String]
    let image2Strengths: [String]
    let image2Weaknesses: [String]
    let nearIdentical: Bool
    let typeMismatch: Bool
    let contentFlag: ContentFlag

    enum CodingKeys: String, CodingKey {
        case jewelryType = "jewelry_type"
        case image1Strengths = "image1_strengths"
        case image1Weaknesses = "image1_weaknesses"
        case image2Strengths = "image2_strengths"
        case image2Weaknesses = "image2_weaknesses"
        case nearIdentical = "near_identical"
        case typeMismatch = "type_mismatch"
        case contentFlag = "content_flag"
    }

    /// Derived list of fusible attributes for dynamic sliders.
    /// Only pairs indices where both sides have a real entry — avoids inventing
    /// a fake counterpart when the backend returns mismatched array lengths.
    var dynamicAttributes: [ChamakAttribute] {
        let pairCount = min(image1Strengths.count, image2Weaknesses.count)
        return (0..<pairCount).map { idx in
            let strength = image1Strengths[idx]
            let weakness = image2Weaknesses[idx]
            return ChamakAttribute(
                id: "attr_\(idx)",
                name: strength.capitalized,
                source1Feature: strength,
                source2Feature: weakness,
                defaultValue: 0.5
            )
        }
    }

    /// image1 strengths with no aligned counterpart in image2's weaknesses —
    /// surfaced in the analysis report instead of being forced into a slider.
    var unmatchedImage1Strengths: [String] {
        let pairCount = min(image1Strengths.count, image2Weaknesses.count)
        return Array(image1Strengths.dropFirst(pairCount))
    }
}

struct ChamakAttribute: Identifiable, Sendable {
    let id: String
    let name: String
    let source1Feature: String
    let source2Feature: String
    var defaultValue: Double
}

// MARK: - Chamak Selected Design Item

struct ChamakDesignItem: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var subtitle: String?
    var imageURL: String?
    var localImageData: Data?
    var product: Product?
    /// SHA256 of the normalized image bytes, set only for direct uploads
    /// (nil for catalogue picks, where `product.id` already guarantees
    /// uniqueness). Lets `canStartAnalysis` catch the same photo being
    /// uploaded to both slots — two custom uploads always get distinct
    /// `id`s (random UUIDs), so `id` equality alone can't detect that.
    var contentHash: String?

    var hasImage: Bool {
        (imageURL != nil && !imageURL!.isEmpty) || (localImageData != nil && !localImageData!.isEmpty)
    }

    static func from(product: Product) -> ChamakDesignItem {
        let url = product.processedImageURL ?? product.imageURL ?? product.rawImageURL ?? ""
        return ChamakDesignItem(
            id: product.id,
            title: product.title ?? "Catalogue Design",
            subtitle: product.jewelleryType?.capitalized ?? "Catalogue Item",
            imageURL: url,
            localImageData: nil,
            product: product,
            contentHash: nil
        )
    }

    static func from(imageData: Data, slot: Int) -> ChamakDesignItem {
        let hash = SHA256.hash(data: imageData).compactMap { String(format: "%02x", $0) }.joined()
        return ChamakDesignItem(
            id: "custom_slot_\(slot)_\(UUID().uuidString)",
            title: "Custom Photo \(slot)",
            subtitle: "Direct Upload",
            imageURL: nil,
            localImageData: imageData,
            product: nil,
            contentHash: hash
        )
    }
}

// MARK: - Wholesaler Form Input

/// Self-describing pairing for one slider, sent alongside `sliderWeights` so
/// the backend doesn't have to re-derive which attribute an index like
/// `attr_0` refers to from `stage1_analysis_json` independently. If that
/// reconstruction ever drifts from the client's, the same index could mean
/// two different attributes on each side with no error raised.
struct WeightedAttribute: Codable, Sendable {
    let id: String
    let attribute: String
    let image1Feature: String
    let image2Feature: String
    let weight: Double

    enum CodingKeys: String, CodingKey {
        case id
        case attribute
        case image1Feature = "image1_feature"
        case image2Feature = "image2_feature"
        case weight
    }
}

struct WholesalerFormInput: Codable, Sendable {
    var sliderWeights: [String: Double]
    var attributeContext: [WeightedAttribute]
    var note: String?

    enum CodingKeys: String, CodingKey {
        case sliderWeights = "slider_weights"
        case attributeContext = "attribute_context"
        case note
    }
}

/// Written to `wholesaler_form_json` for a set-creation row — the sibling of
/// `WholesalerFormInput` for this mode. `backdrop` is also duplicated onto the
/// row's own `set_backdrop` column server-side so usage stays queryable
/// without parsing JSON; the client only ever needs to write this shape.
struct SetCreationInput: Codable, Sendable {
    var backdrop: SetBackdrop
    var note: String?
}

// MARK: - Chamak Generation Row

struct ChamakGeneration: Codable, Identifiable, Sendable {
    let id: UUID
    let wholesalerId: UUID
    let sourceImage1URL: String
    let sourceImage2URL: String
    let stage1AnalysisJSON: Stage1Analysis?
    let wholesalerFormJSON: WholesalerFormInput?
    let noteText: String?
    let compiledPromptText: String?
    let promptVersion: String
    let outputImageURL: String?
    let status: ChamakStatus
    let contentFlagHit: ContentFlag?
    let createdAt: String
    let completedAt: String?
    /// Defaults to `.fusion` on decode so rows written before this column
    /// existed (or a decoder given a payload that omits it) don't fail.
    let mode: ChamakMode
    let setBackdrop: SetBackdrop?

    enum CodingKeys: String, CodingKey {
        case id
        case wholesalerId = "wholesaler_id"
        case sourceImage1URL = "source_image_1_url"
        case sourceImage2URL = "source_image_2_url"
        case stage1AnalysisJSON = "stage1_analysis_json"
        case wholesalerFormJSON = "wholesaler_form_json"
        case noteText = "note_text"
        case compiledPromptText = "compiled_prompt_text"
        case promptVersion = "prompt_version"
        case outputImageURL = "output_image_url"
        case status
        case contentFlagHit = "content_flag_hit"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case mode
        case setBackdrop = "set_backdrop"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        wholesalerId = try container.decode(UUID.self, forKey: .wholesalerId)
        sourceImage1URL = try container.decode(String.self, forKey: .sourceImage1URL)
        sourceImage2URL = try container.decode(String.self, forKey: .sourceImage2URL)
        stage1AnalysisJSON = try container.decodeIfPresent(Stage1Analysis.self, forKey: .stage1AnalysisJSON)
        wholesalerFormJSON = try container.decodeIfPresent(WholesalerFormInput.self, forKey: .wholesalerFormJSON)
        noteText = try container.decodeIfPresent(String.self, forKey: .noteText)
        compiledPromptText = try container.decodeIfPresent(String.self, forKey: .compiledPromptText)
        promptVersion = try container.decode(String.self, forKey: .promptVersion)
        outputImageURL = try container.decodeIfPresent(String.self, forKey: .outputImageURL)
        status = try container.decode(ChamakStatus.self, forKey: .status)
        contentFlagHit = try container.decodeIfPresent(ContentFlag.self, forKey: .contentFlagHit)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        mode = try container.decodeIfPresent(ChamakMode.self, forKey: .mode) ?? .fusion
        setBackdrop = try container.decodeIfPresent(SetBackdrop.self, forKey: .setBackdrop)
    }
}

// MARK: - Feedback

struct ChamakFeedback: Codable, Sendable {
    let id: UUID?
    let chamakGenerationId: UUID
    let satisfied: Bool
    let whatWentWrongText: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case chamakGenerationId = "chamak_generation_id"
        case satisfied
        case whatWentWrongText = "what_went_wrong_text"
        case createdAt = "created_at"
    }
}

// MARK: - Quotes for Loading / Generation Screen

struct ChamakQuote: Sendable {
    let text: String
    let author: String

    static let quotes: [ChamakQuote] = [
        ChamakQuote(
            text: "Jewelry is not just ornament; it is the poetry of metal and stone.",
            author: "Master Craftsman"
        ),
        ChamakQuote(
            text: "True mastery lies in harmonizing classic tradition with bold modern design.",
            author: "Royal Gemologist"
        ),
        ChamakQuote(
            text: "Every jewel carries a soul forged in patience and refined by vision.",
            author: "Ancient Goldsmith Proverb"
        ),
        ChamakQuote(
            text: "Simplicity and luxury meet where flawless geometry meets radiant gold.",
            author: "Design Philosophy"
        ),
        ChamakQuote(
            text: "Synthesizing the best of two creations yields an unmatched masterpiece.",
            author: "JewelIndia Chamak"
        )
    ]
}
