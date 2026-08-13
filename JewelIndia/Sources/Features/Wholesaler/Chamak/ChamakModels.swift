import Foundation

// MARK: - Chamak Status

enum ChamakStatus: String, Codable, Sendable {
    case queued
    case analyzing
    case awaitingInput = "awaiting_input"
    case generating
    case done
    case failed

    var displayLabel: String {
        switch self {
        case .queued: "Queued"
        case .analyzing: "Analyzing Designs"
        case .awaitingInput: "Awaiting Input"
        case .generating: "Fusing Designs"
        case .done: "Fusion Complete"
        case .failed: "Generation Failed"
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
            return "One or both selected images do not appear to be jewelry. Please select jewelry designs from your catalogue."
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

    /// Derived list of fusible attributes for dynamic sliders
    var dynamicAttributes: [ChamakAttribute] {
        var items: [ChamakAttribute] = []
        for (idx, strength) in image1Strengths.enumerated() {
            let weakness = idx < image2Weaknesses.count ? image2Weaknesses[idx] : "Alternative styling"
            items.append(ChamakAttribute(
                id: "attr_\(idx)",
                name: strength.capitalized,
                source1Feature: strength,
                source2Feature: weakness,
                defaultValue: 0.5
            ))
        }
        return items
    }
}

struct ChamakAttribute: Identifiable, Sendable {
    let id: String
    let name: String
    let source1Feature: String
    let source2Feature: String
    var defaultValue: Double
}

// MARK: - Wholesaler Form Input

struct WholesalerFormInput: Codable, Sendable {
    var sliderWeights: [String: Double]
    var note: String?

    enum CodingKeys: String, CodingKey {
        case sliderWeights = "slider_weights"
        case note
    }
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
