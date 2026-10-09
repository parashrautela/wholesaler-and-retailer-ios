import CryptoKit
import Foundation
import SwiftUI

/// Whose designs the Chamak picker offers.
enum ChamakCatalogueSource: Sendable {
    /// A wholesaler's own products.
    case ownProducts
    /// A retailer's shortlist and customer boards.
    case storeDesigns
}

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
        case .generating: mode == .setCreation ? "Staging Your Set" : "Combining Designs"
        case .done: mode == .setCreation ? "Set Complete" : "Designs Combined"
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

    /// `set_backdrop` is a bare TEXT column with no CHECK constraint behind it
    /// (migration 005), so it can hold a preset id this build does not know —
    /// an older or newer one. `.velvetBust` is the pipeline's own
    /// `DEFAULT_SET_BACKDROP`, so falling back to it keeps the row readable
    /// instead of throwing the whole gallery away.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SetBackdrop(rawValue: raw) ?? .velvetBust
    }

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

// Safe, staging-only shortcuts shown in the Set Creation styling screen.
// Their instruction text is sent as part of the staging note; the backend
// still applies its preservation rules so chips cannot redesign the pieces.
struct SetStylingChip: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let instruction: String

    static let all: [SetStylingChip] = [
        SetStylingChip(id: "balanced", label: "Balanced", instruction: "Arrange both pieces in a balanced, harmonious composition with clear separation."),
        SetStylingChip(id: "equal_focus", label: "Equal focus", instruction: "Give both jewelry pieces equal visual importance and prominence."),
        SetStylingChip(id: "luxury", label: "Luxury showroom", instruction: "Use premium showroom spacing, refined presentation, and an elegant luxury mood."),
        SetStylingChip(id: "minimal", label: "Minimal", instruction: "Use a clean, minimal arrangement with generous negative space."),
        SetStylingChip(id: "soft_light", label: "Soft light", instruction: "Use soft diffused lighting with gentle shadows and subtle jewelry highlights."),
        SetStylingChip(id: "detail", label: "Show detail", instruction: "Frame the pieces close enough to clearly show fine craftsmanship and gemstone details."),
        SetStylingChip(id: "more_space", label: "More breathing room", instruction: "Keep generous space around both pieces so no component feels crowded or hidden."),
        SetStylingChip(id: "ecommerce", label: "E-commerce ready", instruction: "Use a clean professional catalogue arrangement suitable for an online product listing.")
    ]
}

// MARK: - Content Flag

enum ContentFlag: String, Codable, Sendable {
    case ok
    case notJewelry = "not_jewelry"
    case inappropriate
    case tooUnclearToAssess = "too_unclear_to_assess"

    /// The pipeline validates this value before writing the `content_flag_hit`
    /// *column* (`chamak.py:178`) but writes whatever the vision model returned
    /// straight into `stage1_analysis_json` (`chamak.py:111`). So the blob can
    /// legally hold a value this enum has never heard of, and a strict decode
    /// there throws — which, decoded as part of an array, discards every other
    /// row with it. Falling back to `.ok` mirrors what the column already does.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ContentFlag(rawValue: raw) ?? .ok
    }

    var userMessage: String? {
        switch self {
        case .ok:
            return nil
        case .notJewelry:
            return "Jewellery was not detected in one or both selected images. Please select two clear jewellery photos to continue."
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
    /// The full-size image. This is what gets sent to the AI, so it must
    /// never be swapped for a small copy — `displayURL` is what the UI shows.
    var imageURL: String?
    var localImageData: Data?
    var product: Product?
    /// SHA256 of the normalized image bytes, set only for direct uploads
    /// (nil for catalogue picks, where `product.id` already guarantees
    /// uniqueness). Lets `canStartAnalysis` catch the same photo being
    /// uploaded to both slots — two custom uploads always get distinct
    /// `id`s (random UUIDs), so `id` equality alone can't detect that.
    var contentHash: String?
    var declaredJewelleryType: String?

    var canonicalJewelleryType: String? {
        if let declared = declaredJewelleryType {
            return JewelleryTypeCanonical.canonicalize(declared)
        }
        if let pType = product?.jewelleryType {
            return JewelleryTypeCanonical.canonicalize(pType)
        }
        return nil
    }

    var displayTypeLabel: String {
        if let c = canonicalJewelleryType {
            return JewelleryTypeCanonical.displayLabel(for: c)
        }
        return subtitle ?? "Piece"
    }

    var hasImage: Bool {
        (imageURL != nil && !imageURL!.isEmpty) || (localImageData != nil && !localImageData!.isEmpty)
    }

    /// What to draw for this design, at the size the view needs. Falls back to
    /// the full-size image when this pick has no stored copies.
    func displayURL(_ size: ImageSize) -> URL? {
        guard let imageURL, !imageURL.isEmpty else { return nil }
        return product?.url(for: imageURL, size: size) ?? URL(string: imageURL)
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
            contentHash: nil,
            declaredJewelleryType: nil
        )
    }

    static func from(imageData: Data, slot: Int, declaredJewelleryType: String? = nil) -> ChamakDesignItem {
        let hash = SHA256.hash(data: imageData).compactMap { String(format: "%02x", $0) }.joined()
        let label = declaredJewelleryType.flatMap { JewelleryTypeCanonical.displayLabel(for: $0) } ?? "Direct Upload"
        return ChamakDesignItem(
            id: "custom_slot_\(slot)_\(UUID().uuidString)",
            title: "Custom Photo \(slot)",
            subtitle: label,
            imageURL: nil,
            localImageData: imageData,
            product: nil,
            contentHash: hash,
            declaredJewelleryType: declaredJewelleryType
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

struct SetCreationOutput: Codable, Sendable {
    let path: String
    let variants: [String: String]
}

// MARK: - Chamak Generation Row

struct ChamakGeneration: Codable, Identifiable, Sendable {
    let id: UUID
    let wholesalerId: UUID
    let sourceImage1URL: String
    let sourceImage2URL: String
    /// Optional slots used only by Set Creation. Keeping these on the row
    /// means the result and gallery can reconstruct a four-piece set after
    /// the active flow model has been released.
    let sourceImage3URL: String?
    let sourceImage4URL: String?
    let stage1AnalysisJSON: Stage1Analysis?
    let wholesalerFormJSON: WholesalerFormInput?
    let noteText: String?
    let compiledPromptText: String?
    let promptVersion: String
    let outputImageURL: String?
    /// Small copies of the output, as paths in the same private bucket:
    /// `{"card"|"detail"|"full": path}` (migration 010). Empty for anything
    /// generated before the pipeline started writing them, which is why
    /// `outputPath(_:)` falls back to the full-size original.
    let outputVariants: [String: String]
    let outputImages: [SetCreationOutput]
    let status: ChamakStatus
    let contentFlagHit: ContentFlag?
    let createdAt: String
    let completedAt: String?
    /// Defaults to `.fusion` on decode so rows written before this column
    /// existed (or a decoder given a payload that omits it) don't fail.
    let mode: ChamakMode
    let setBackdrop: SetBackdrop?

    /// Reuse the saved analysis reason when reopening failed jobs as well as polling.
    var failureUserMessage: String {
        contentFlagHit?.userMessage
            ?? stage1AnalysisJSON?.contentFlag.userMessage
            ?? "AI generation could not complete. Please try again or report the issue."
    }

    enum CodingKeys: String, CodingKey {
        case id
        case wholesalerId = "wholesaler_id"
        case sourceImage1URL = "source_image_1_url"
        case sourceImage2URL = "source_image_2_url"
        case sourceImage3URL = "source_image_3_url"
        case sourceImage4URL = "source_image_4_url"
        case stage1AnalysisJSON = "stage1_analysis_json"
        case wholesalerFormJSON = "wholesaler_form_json"
        case noteText = "note_text"
        case compiledPromptText = "compiled_prompt_text"
        case promptVersion = "prompt_version"
        case outputImageURL = "output_image_url"
        case outputVariants = "output_variants"
        case outputImages = "output_images"
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
        sourceImage3URL = try container.decodeIfPresent(String.self, forKey: .sourceImage3URL)
        sourceImage4URL = try container.decodeIfPresent(String.self, forKey: .sourceImage4URL)
        // `decodeIfPresent` only tolerates an ABSENT key — a key that is present
        // but holds an unexpected shape still throws, and because the gallery
        // decodes `[ChamakGeneration]`, one bad blob discards every row in the
        // response. Both of these are JSONB with no schema enforced by the
        // database, written by the pipeline from a model's free-form output, so
        // a shape drift is a question of when, not if. Degrade to nil: the
        // gallery card never reads either field, and the flow already handles
        // nil because both are null until stage 1 finishes.
        stage1AnalysisJSON = try? container.decodeIfPresent(Stage1Analysis.self, forKey: .stage1AnalysisJSON)
        wholesalerFormJSON = try? container.decodeIfPresent(WholesalerFormInput.self, forKey: .wholesalerFormJSON)
        noteText = try container.decodeIfPresent(String.self, forKey: .noteText)
        compiledPromptText = try container.decodeIfPresent(String.self, forKey: .compiledPromptText)
        promptVersion = try container.decode(String.self, forKey: .promptVersion)
        outputImageURL = try container.decodeIfPresent(String.self, forKey: .outputImageURL)
        outputVariants = (try? container.decodeIfPresent([String: String].self, forKey: .outputVariants)) ?? [:]
        outputImages = (try? container.decodeIfPresent([SetCreationOutput].self, forKey: .outputImages)) ?? []
        status = try container.decode(ChamakStatus.self, forKey: .status)
        contentFlagHit = try container.decodeIfPresent(ContentFlag.self, forKey: .contentFlagHit)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        mode = try container.decodeIfPresent(ChamakMode.self, forKey: .mode) ?? .fusion
        setBackdrop = try container.decodeIfPresent(SetBackdrop.self, forKey: .setBackdrop)
    }

    /// The stored path to sign for a given size — the small copy when the
    /// pipeline made one, the full-size output otherwise. A gallery tile
    /// asking for `.card` fetches ~41 KB instead of a multi-megabyte PNG.
    func outputPath(_ size: ImageSize) -> String? {
        outputVariants[size.rawValue] ?? outputImageURL
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

// MARK: - Chamak Slot
enum ChamakSlot {
    static func label(for slot: Int, mode: ChamakMode) -> String {
        switch (mode, slot) {
        case (.setCreation, let n): "Piece \(n)"
        case (_, 1): "Design 1"
        default: "Design 2"
        }
    }

    static func color(for slot: Int) -> SwiftUI.Color {
        switch slot {
        case 1: SwiftUI.Color(hex: 0xCA8A04)
        case 2: SwiftUI.Color(hex: 0x3B82F6)
        case 3: SwiftUI.Color(hex: 0x10B981)
        default: SwiftUI.Color(hex: 0xE11D48)
        }
    }
}

// MARK: - Canonical Jewellery Type

/// Canonical jewellery type normalizer and taxonomy for Set Creation.
/// Ensures cross-platform agreement between iOS, Web, and AI pipeline.
enum JewelleryTypeCanonical: String, CaseIterable, Sendable, Identifiable {
    case chain
    case necklace
    case ring
    case earrings
    case bangle
    case pendant
    case nosepin
    case haram
    case mangalsutra

    var id: String { rawValue }

    static var allCanonical: [String] {
        allCases.map(\.rawValue)
    }

    var displayLabel: String {
        switch self {
        case .chain: "Chains"
        case .necklace: "Necklace"
        case .ring: "Ring"
        case .earrings: "Earrings"
        case .bangle: "Bangle"
        case .pendant: "Pendant"
        case .nosepin: "Nosepin"
        case .haram: "Haram"
        case .mangalsutra: "Mangalsutra"
        }
    }

    /// Normalizes raw jewellery type string to its canonical key.
    /// Material categories (e.g. "gold", "silver") return nil because material
    /// must never be used to determine jewellery type uniqueness.
    static func canonicalize(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "chain", "chains", "neck chain", "neck chains":
            return JewelleryTypeCanonical.chain.rawValue
        case "necklace", "necklaces":
            return JewelleryTypeCanonical.necklace.rawValue
        case "ring", "rings":
            return JewelleryTypeCanonical.ring.rawValue
        case "earring", "earrings", "jhumka", "jhumkas":
            return JewelleryTypeCanonical.earrings.rawValue
        case "bangle", "bangles":
            return JewelleryTypeCanonical.bangle.rawValue
        case "pendant", "pendants":
            return JewelleryTypeCanonical.pendant.rawValue
        case "nosepin", "nosepins", "nose pin", "nose pins":
            return JewelleryTypeCanonical.nosepin.rawValue
        case "haram", "harams":
            return JewelleryTypeCanonical.haram.rawValue
        case "mangalsutra", "mangalsutras":
            return JewelleryTypeCanonical.mangalsutra.rawValue
        default:
            return nil
        }
    }

    static func displayLabel(for canonicalKey: String) -> String {
        JewelleryTypeCanonical(rawValue: canonicalKey)?.displayLabel ?? canonicalKey.capitalized
    }
}

