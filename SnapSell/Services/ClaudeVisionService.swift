import Foundation
import UIKit

// MARK: - Claude Vision Service

class ClaudeVisionService: VisionServiceProtocol {

    static let shared = ClaudeVisionService()
    private init() {}

    private let session = URLSession.shared

    // MARK: - Public API

    /// Send a photo to Claude and get back a structured IdentifiedItem
    func identifyItem(image: UIImage) async throws -> IdentifiedItem {
        // 1568px is the threshold where Claude processes images at full detail.
        // Below this, pixels are upsampled internally and fine features (port type,
        // Dynamic Island vs notch, camera arrangement) become harder to distinguish.
        // Progressive quality fallback keeps the payload under the 5 MB API limit.
        let resized = image.resizedToMaxDimension(1568)

        let limit = 5_100_000
        let qualities: [CGFloat] = [0.85, 0.7, 0.5, 0.3]
        var imageData: Data?
        for q in qualities {
            if let d = resized.jpegData(compressionQuality: q), d.count < limit {
                imageData = d
                break
            }
        }

        guard let imageData else { throw VisionError.imageEncodingFailed }

        let base64Image = imageData.base64EncodedString()
        let requestBody = buildRequestBody(base64Image: base64Image)
        let data = try await sendRequest(body: requestBody)
        return try parseResponse(data: data)
    }

    // MARK: - Request Building

    private func buildRequestBody(base64Image: String) -> [String: Any] {
        let systemPrompt = """
        You are an expert item identification AI for a reselling app. \
        Exact model identification directly affects resale value — do not guess or round up to a \
        more familiar model when visual evidence is ambiguous.

        Before committing to an identification, mentally work through the distinguishing hardware \
        features visible in the image. Pay close attention to:

        SMARTPHONES & TABLETS
        • Display cutout: pill-shaped Dynamic Island (iPhone 14 Pro / 15 / 16 series) vs. notch \
        (iPhone X–14 non-Pro) vs. punch-hole vs. full-screen
        • Port at bottom: USB-C (iPhone 15+, all Android flagships) vs. Lightning (iPhone 14 and earlier)
        • Camera system: number of lenses, triangular vs. linear arrangement, periscope zoom bump
        • Side button layout: Action Button (iPhone 15 Pro+) vs. standard mute switch
        • Frame material: titanium (15 Pro / 16 Pro) vs. aluminum (standard models)
        • Camera bump shape and size differences between generations

        SNEAKERS & SHOES
        • Sole profile, colorway name, visible size tag, outsole pattern, toe-box shape
        • Logo style and placement (e.g. Nike Swoosh angle, Jordan Wings position)

        ELECTRONICS & ACCESSORIES
        • Any model number printed or embossed on the device body
        • Port and connector types, antenna bands, button count and placement
        • Generation-specific design cues (e.g. rounded vs. flat edges)

        CLOTHING & APPAREL
        • Visible tags, logo embroidery details, hardware (zipper pulls, buttons), colorway

        GENERAL RULES
        • If two similar models share an identical appearance and the distinguishing feature is not \
        clearly visible, set confidenceScore below 0.70 and note what was ambiguous in the model field.
        • Never inflate confidence. A confident wrong answer is worse than an honest uncertain one.
        • The name and model fields should be exactly what a seller would type into eBay search.

        Return ONLY a valid JSON object — no markdown, no explanation, no code fences:

        {
          "name": "Full descriptive item name including specific generation/variant",
          "brand": "Brand name or null",
          "category": "Main category (e.g. Sneakers, Electronics, Clothing, Collectibles)",
          "subcategory": "Subcategory or null",
          "description": "2-3 sentence eBay-style listing description calling out model-specific details",
          "keywords": ["keyword1", "keyword2", "keyword3", "keyword4", "keyword5"],
          "confidenceScore": 0.97,
          "suggestedCondition": "good",
          "estimatedYear": "2019" or null,
          "color": "primary color or null",
          "size": "size if visible or null",
          "model": "exact model number/name, or closest match with ambiguity noted"
        }

        Valid suggestedCondition values: "newWithTags", "newWithoutTags", "newOther", "likeNew", "good", "acceptable", "forParts"
        """

        let userMessage: [String: Any] = [
            "role": "user",
            "content": [
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": base64Image
                    ]
                ],
                [
                    "type": "text",
                    "text": "Identify this item precisely for eBay reselling. Check all visible hardware details before deciding the exact model. Return only the JSON object."
                ]
            ]
        ]

        // Extended thinking gives Claude a reasoning budget to work through visual ambiguities
        // (e.g. iPhone 13 Pro Max vs 15 Pro Max) before committing to the JSON answer.
        // budget_tokens controls how much internal reasoning is allowed; it does not appear
        // in the output. max_tokens must exceed budget_tokens + expected JSON output (~400).
        return [
            "model": APIConfig.claudeModel,
            "max_tokens": 6000,
            "thinking": [
                "type": "enabled",
                "budget_tokens": 5000
            ],
            "system": systemPrompt,
            "messages": [userMessage]
        ]
    }

    // MARK: - Network

    private func sendRequest(body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(APIConfig.anthropicBaseURL)/messages") else {
            throw VisionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(APIConfig.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue(APIConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VisionError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        return data
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data) throws -> IdentifiedItem {
        // Anthropic response envelope
        struct AnthropicResponse: Codable {
            struct Content: Codable {
                let type: String
                let text: String?
            }
            let content: [Content]
        }

        let envelope = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        // When extended thinking is enabled the content array contains a "thinking" block
        // followed by the "text" block. We only need the text block.
        guard let text = envelope.content.first(where: { $0.type == "text" })?.text else {
            throw VisionError.emptyResponse
        }

        // Strip any accidental markdown code fences
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw VisionError.parseError("Could not encode response as UTF-8")
        }

        // Decode the structured item response
        struct RawItemResponse: Codable {
            let name: String
            let brand: String?
            let category: String
            let subcategory: String?
            let description: String
            let keywords: [String]
            let confidenceScore: Double
            let suggestedCondition: String
            let estimatedYear: String?
            let color: String?
            let size: String?
            let model: String?
        }

        let raw = try JSONDecoder().decode(RawItemResponse.self, from: jsonData)

        let condition = ItemCondition.parse(raw.suggestedCondition)

        return IdentifiedItem(
            name: raw.name,
            brand: raw.brand,
            category: raw.category,
            subcategory: raw.subcategory,
            description: raw.description,
            keywords: raw.keywords,
            confidenceScore: raw.confidenceScore,
            suggestedCondition: condition,
            estimatedYear: raw.estimatedYear,
            color: raw.color,
            size: raw.size,
            model: raw.model
        )
    }
}

// MARK: - Errors

enum VisionError: LocalizedError {
    case imageEncodingFailed
    case invalidURL
    case invalidResponse
    case emptyResponse
    case apiError(statusCode: Int, message: String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "Could not encode image for upload."
        case .invalidURL: return "Invalid API URL."
        case .invalidResponse: return "Invalid server response."
        case .emptyResponse: return "Empty response from AI."
        case .apiError(let code, let msg): return "API Error \(code): \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
