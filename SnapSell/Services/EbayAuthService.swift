import Foundation
import AuthenticationServices

// MARK: - eBay Auth Service

class EbayAuthService: NSObject, ObservableObject {

    static let shared = EbayAuthService()
    private override init() { super.init() }

    @Published var isAuthenticated = false
    @Published var isAuthenticating = false

    private var webAuthSession: ASWebAuthenticationSession?
    private var accessToken: String = ""
    private var tokenExpiry: Date = .distantPast

    // MARK: - Public

    var currentToken: String {
        get async throws {
            if isTokenValid() {
                return accessToken
            }
            if !APIConfig.ebayRefreshToken.isEmpty {
                return try await refreshAccessToken()
            }
            throw EbayAuthError.notAuthenticated
        }
    }

    /// Launch eBay OAuth web flow
    func authenticate(presentationAnchor: ASPresentationAnchor) async throws {
        await MainActor.run { isAuthenticating = true }

        let authURL = buildAuthURL()
        guard let url = URL(string: authURL) else {
            throw EbayAuthError.invalidURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "snapsell"
            ) { [weak self] callbackURL, error in
                guard let self else { return }

                Task { @MainActor in
                    self.isAuthenticating = false
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == "code" })?
                        .value
                else {
                    continuation.resume(throwing: EbayAuthError.missingAuthCode)
                    return
                }

                Task {
                    do {
                        try await self.exchangeCodeForToken(code: code)
                        await MainActor.run { self.isAuthenticated = true }
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            session.start()
        }
    }

    func signOut() {
        accessToken = ""
        tokenExpiry = .distantPast
        UserDefaults.standard.removeObject(forKey: "ebay_user_token")
        UserDefaults.standard.removeObject(forKey: "ebay_refresh_token")
        isAuthenticated = false
    }

    // MARK: - Private

    private func buildAuthURL() -> String {
        var components = URLComponents(string: APIConfig.ebayOAuthURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: APIConfig.ebayClientID),
            URLQueryItem(name: "redirect_uri", value: APIConfig.ebayRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: APIConfig.ebayScopes),
            URLQueryItem(name: "prompt", value: "login")
        ]
        return components.url?.absoluteString ?? ""
    }

    private func exchangeCodeForToken(code: String) async throws {
        guard let url = URL(string: APIConfig.ebayTokenURL) else {
            throw EbayAuthError.invalidURL
        }

        let credentials = "\(APIConfig.ebayClientID):\(APIConfig.ebayClientSecret)"
        guard let credData = credentials.data(using: .utf8) else {
            throw EbayAuthError.encodingError
        }
        let base64Creds = credData.base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Creds)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(APIConfig.ebayRedirectURI)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EbayAuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeTokens(tokenResponse)
    }

    private func refreshAccessToken() async throws -> String {
        guard let url = URL(string: APIConfig.ebayTokenURL) else {
            throw EbayAuthError.invalidURL
        }

        let credentials = "\(APIConfig.ebayClientID):\(APIConfig.ebayClientSecret)"
        let base64Creds = Data(credentials.utf8).base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Creds)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let refreshToken = APIConfig.ebayRefreshToken
        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EbayAuthError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeTokens(tokenResponse)
        return tokenResponse.accessToken
    }

    private func storeTokens(_ response: TokenResponse) {
        accessToken = response.accessToken
        tokenExpiry = Date().addingTimeInterval(Double(response.expiresIn - 60))
        UserDefaults.standard.set(response.accessToken, forKey: "ebay_user_token")
        if let rt = response.refreshToken {
            UserDefaults.standard.set(rt, forKey: "ebay_refresh_token")
        }
    }

    private func isTokenValid() -> Bool {
        !accessToken.isEmpty && Date() < tokenExpiry
    }

    // MARK: - Token Response

    struct TokenResponse: Codable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension EbayAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - Errors

enum EbayAuthError: LocalizedError {
    case invalidURL
    case missingAuthCode
    case tokenExchangeFailed
    case tokenRefreshFailed
    case notAuthenticated
    case encodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid OAuth URL."
        case .missingAuthCode: return "Missing authorization code from eBay."
        case .tokenExchangeFailed: return "Failed to exchange code for token."
        case .tokenRefreshFailed: return "Failed to refresh access token."
        case .notAuthenticated: return "Not authenticated with eBay. Please sign in."
        case .encodingError: return "Failed to encode credentials."
        }
    }
}
