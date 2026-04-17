import Foundation
import UIKit

// MARK: - Protocol

protocol VisionServiceProtocol {
    func identifyItem(image: UIImage) async throws -> IdentifiedItem
}

// MARK: - Manager

/// Routes vision calls to the active provider (Claude cloud or a local LLM).
/// Switch providers in Profile → AI Configuration without changing call sites.
class VisionServiceManager {

    static let shared = VisionServiceManager()
    private init() {}

    var activeService: VisionServiceProtocol {
        APIConfig.localLLMEnabled ? LocalLLMService.shared : ClaudeVisionService.shared
    }

    func identifyItem(image: UIImage) async throws -> IdentifiedItem {
        try await activeService.identifyItem(image: image)
    }
}
