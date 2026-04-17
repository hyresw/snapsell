import SwiftUI

// MARK: - Scan Flow State

enum ScanFlowScreen {
    case camera
    case analyzing
    case error(String)                                          // ← explicit error state
    case results(IdentifiedItem, PriceAnalysis, UIImage)
    case createListing(DraftListing, PriceAnalysis)
    case success(PostedListingResponse)
}

// MARK: - ScanFlowView

struct ScanFlowView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentScreen: ScanFlowScreen = .camera
    @State private var previousResultsScreen: ScanFlowScreen = .camera

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch currentScreen {
            case .camera:
                CameraView(onCapture: handleCapture)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .transition(.opacity)

            case .analyzing:
                AnalyzingView()
                    .transition(.opacity)

            case .error(let message):
                ScanErrorView(message: message, onRetry: resetToCamera)
                    .transition(.opacity)

            case .results(let item, let analysis, let image):
                NavigationStack {
                    ResultsView(
                        item: item,
                        priceAnalysis: analysis,
                        capturedImage: image,
                        onListTap: {
                            let draft = DraftListing(from: item, suggestedPrice: analysis.suggestedPrice, image: image)
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentScreen = .createListing(draft, analysis)
                            }
                        },
                        onRescan: resetToCamera
                    )
                }
                .transition(.move(edge: .trailing))

            case .createListing(let draft, let analysis):
                CreateListingView(
                    draft: draft,
                    priceAnalysis: analysis,
                    onBack: {
                        if case .results(let item, let pa, let img) = previousResultsScreen {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentScreen = .results(item, pa, img)
                            }
                        }
                    },
                    onSuccess: { response in
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentScreen = .success(response)
                        }
                    }
                )
                .transition(.move(edge: .trailing))

            case .success(let response):
                SuccessView(response: response, onScanAnother: resetToCamera)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: screenKey)
    }

    private var screenKey: String {
        switch currentScreen {
        case .camera:        return "camera"
        case .analyzing:     return "analyzing"
        case .error:         return "error"
        case .results:       return "results"
        case .createListing: return "createListing"
        case .success:       return "success"
        }
    }

    // MARK: - Capture Handler

    private func handleCapture(image: UIImage) {
        // Guard: cloud Claude needs an API key; local LLM just needs the server running.
        if !APIConfig.localLLMEnabled {
            let key = APIConfig.anthropicAPIKey
            guard key != "YOUR_ANTHROPIC_API_KEY", !key.isEmpty else {
                withAnimation {
                    currentScreen = .error("Anthropic API key is not set.\n\nGo to the Profile tab → AI Configuration to add your key from console.anthropic.com.")
                }
                return
            }
        }

        withAnimation { currentScreen = .analyzing }

        Task {
            do {
                let item = try await VisionServiceManager.shared.identifyItem(image: image)
                // eBay search never throws — returns empty analysis if nothing found
                let analysis = await EbayMarketplaceService.shared.searchSoldListings(for: item)
                let entry = ScanHistoryEntry(item: item, analysis: analysis, image: image)
                await MainActor.run { appState.appendScanHistory(entry) }
                await MainActor.run {
                    let screen = ScanFlowScreen.results(item, analysis, image)
                    self.previousResultsScreen = screen
                    withAnimation(.easeInOut(duration: 0.4)) { currentScreen = screen }
                }
            } catch {
                await MainActor.run {
                    withAnimation { currentScreen = .error(friendlyError(error)) }
                }
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()

        if APIConfig.localLLMEnabled {
            if lower.contains("could not connect") || lower.contains("connection refused")
                || lower.contains("network connection") || lower.contains("url session") {
                let url = APIConfig.localLLMBaseURL
                let model = APIConfig.localLLMModel
                return "Could not reach the local LLM server.\n\nExpected: \(url)\nModel: \(model)\n\nMake sure Ollama or LM Studio is running on your Mac and the iPhone is on the same Wi-Fi network.\n\nOllama: ollama serve\nLM Studio: enable local server in app settings.\n\nError: \(raw)"
            }
            if lower.contains("404") {
                return "Model '\(APIConfig.localLLMModel)' not found on the server.\n\nFor Ollama run: ollama pull \(APIConfig.localLLMModel)\n\nError: \(raw)"
            }
            return "Local LLM recognition failed.\n\nError: \(raw)"
        }

        if lower.contains("credit") || lower.contains("balance") || lower.contains("billing") {
            return "Your Anthropic API credits are exhausted.\n\nAdd credits at:\nconsole.anthropic.com/settings/billing\n\nThen try again."
        }
        if lower.contains("401") || lower.contains("unauthorized") {
            return "Invalid Anthropic API key (401).\n\nGo to Profile → AI Configuration and re-enter your key."
        }
        if lower.contains("model") {
            return "The AI model is unavailable.\n\nCheck console.anthropic.com to verify your API key has access.\n\nError: \(raw)"
        }
        return "Recognition failed.\n\nError: \(raw)"
    }

    private func resetToCamera() {
        withAnimation(.easeInOut(duration: 0.3)) { currentScreen = .camera }
    }
}

// MARK: - Error Screen

struct ScanErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 88, height: 88)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(.red)
                        }
                        .padding(.top, 60)

                        Text("Could Not Identify Item")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)

                        // Full error — scrollable so nothing is cut off
                        Text(message)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 32)
                }

                // Retry pinned to bottom
                Button(action: onRetry) {
                    Text("Try Again")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color("AccentYellow"), in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
    }
}
