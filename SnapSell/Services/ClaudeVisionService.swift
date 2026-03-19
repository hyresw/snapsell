import Foundation
import UIKit

// MARK: - Claude Vision Service

class ClaudeVisionService {

    static let shared = ClaudeVisionService()
    private init() {}

    private let session = URLSession.shared

    // MARK: - Public API

    /// Send a photo to Claude and get back a structured IdentifiedItem
    func identifyItem(image: UIImage) async throws -> IdentifiedItem {
        // 1568px gives Claude enough detail to read brand logos and model numbers.
        // Progressive quality fallback keeps the payload under the 5 MB API limit.
        let resized = image.resizedToMaxDimension(1200)

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
        When given an image, identify the item and return ONLY a valid JSON object with no markdown, \
        no explanation, no code fences. Return exactly this structure:

        {
          "name": "Full descriptive item name",
          "brand": "Brand name or null",
          "category": "Main category (e.g. Sneakers, Electronics, Clothing, Collectibles)",
          "subcategory": "Subcategory or null",
          "description": "2-3 sentence eBay-style listing description",
          "keywords": ["keyword1", "keyword2", "keyword3", "keyword4", "keyword5"],
          "confidenceScore": 0.97,
          "suggestedCondition": "good",
          "estimatedYear": "2019" or null,
          "color": "primary color or null",
          "size": "size if visible or null",
          "model": "model number/name if known or null"
        }

        Valid suggestedCondition values: "newWithTags", "newWithoutTags", "newOther", "likeNew", "good", "acceptable", "forParts"

        Be specific and accurate. Include brand, model, size if visible. \
        The name should be exactly what a seller would search on eBay.
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
                    "text": "Identify this item for eBay reselling. Return only the JSON object."
                ]
            ]
        ]

        return [
            "model": APIConfig.claudeModel,
            "max_tokens": 1024,
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

        let condition = ItemCondition(rawValue: raw.suggestedCondition) ?? .good

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
