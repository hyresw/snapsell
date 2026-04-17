import Foundation
import UIKit

// MARK: - Local LLM Vision Service
//
// Connects to any OpenAI-compatible local server (Ollama, LM Studio) that hosts
// a vision-capable model such as Gemma 3, Qwen2.5-VL, LLaVA, or Moondream.
//
// Ollama setup:
//   brew install ollama && ollama pull gemma3:12b
//   ollama serve            # starts at http://localhost:11434
//
// LM Studio setup:
//   Download from lmstudio.ai, load a VLM, enable the local server (port 1234).

class LocalLLMService: VisionServiceProtocol {

    static let shared = LocalLLMService()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180   // local inference can be slow
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    // MARK: - VisionServiceProtocol

    func identifyItem(image: UIImage) async throws -> IdentifiedItem {
        let resized = image.resizedToMaxDimension(1568)

        // Local models typically accept larger payloads than cloud APIs, but we
        // still compress so the base64 string stays manageable for the context window.
        let limit = 10_000_000
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
        // Same identification prompt used for Claude so switching providers doesn't
        // change the expected output schema.
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
          "estimatedYear": "2019",
          "color": "primary color or null",
          "size": "size if visible or null",
          "model": "exact model number/name, or closest match with ambiguity noted"
        }

        Valid suggestedCondition values: "newWithTags", "newWithoutTags", "newOther", "likeNew", "good", "acceptable", "forParts"
        """

        // OpenAI multimodal message format — supported by Ollama and LM Studio
        let userContent: [[String: Any]] = [
            [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]
            ],
            [
                "type": "text",
                "text": "Identify this item precisely for eBay reselling. Check all visible hardware details before deciding the exact model. Return only the JSON object."
            ]
        ]

        return [
            "model": APIConfig.localLLMModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "stream": false,
            "temperature": 0.1   // low temperature keeps the JSON output stable
        ]
    }

    // MARK: - Network

    private func sendRequest(body: [String: Any]) async throws -> Data {
        let base = APIConfig.localLLMBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw VisionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let envelope = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = envelope.choices.first?.message.content else {
            throw VisionError.emptyResponse
        }

        // Strip markdown fences if the model added them
        var cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Some models prepend explanation text before the JSON; extract the object.
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw VisionError.parseError("Could not encode response as UTF-8")
        }

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
