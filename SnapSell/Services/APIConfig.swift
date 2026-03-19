import Foundation

/// Central place for all API credentials.
/// In production, load these from Keychain or a remote config — never hardcode in source.
enum APIConfig {

    // MARK: - Anthropic (Claude Vision)
    /// Get your key at https://console.anthropic.com
    static var anthropicAPIKey: String {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "anthropic_api_key")
            ?? "YOUR_ANTHROPIC_API_KEY"
    }

    static let anthropicBaseURL = "https://api.anthropic.com/v1"
    static let claudeModel = "claude-opus-4-6"
    static let anthropicVersion = "2023-06-01"

    // MARK: - eBay
    /// Register at https://developer.ebay.com
    /// Use sandbox credentials for testing, production for live
    static var ebayClientID: String {
        ProcessInfo.processInfo.environment["EBAY_CLIENT_ID"]
            ?? UserDefaults.standard.string(forKey: "ebay_client_id")
            ?? "YOUR_EBAY_CLIENT_ID"
    }

    static var ebayClientSecret: String {
        ProcessInfo.processInfo.environment["EBAY_CLIENT_SECRET"]
            ?? UserDefaults.standard.string(forKey: "ebay_client_secret")
            ?? "YOUR_EBAY_CLIENT_SECRET"
    }

    static var ebayUserToken: String {
        // Set after OAuth flow completes
        UserDefaults.standard.string(forKey: "ebay_user_token") ?? ""
    }

    static var ebayRefreshToken: String {
        UserDefaults.standard.string(forKey: "ebay_refresh_token") ?? ""
    }

    /// Automatically true when the stored App ID is a sandbox key (-SBX-).
    /// Switches all eBay base URLs without any manual toggle.
    static var useSandbox: Bool {
        ebayClientID.uppercased().contains("-SBX-")
    }

    static var ebayBaseURL: String {
        useSandbox ? "https://api.sandbox.ebay.com" : "https://api.ebay.com"
    }

    static var ebayOAuthURL: String {
        useSandbox
            ? "https://auth.sandbox.ebay.com/oauth2/authorize"
            : "https://auth.ebay.com/oauth2/authorize"
    }

    static var ebayTokenURL: String {
        useSandbox
            ? "https://api.sandbox.ebay.com/identity/v1/oauth2/token"
            : "https://api.ebay.com/identity/v1/oauth2/token"
    }

    // Redirect URI registered in your eBay developer app
    static let ebayRedirectURI = "snapsell://oauth/callback"

    // Scopes needed for reading sold listings and creating listings
    static let ebayScopes = [
        "https://api.ebay.com/oauth/api_scope",
        "https://api.ebay.com/oauth/api_scope/sell.inventory",
        "https://api.ebay.com/oauth/api_scope/sell.account",
        "https://api.ebay.com/oauth/api_scope/sell.fulfillment",
        "https://api.ebay.com/oauth/api_scope/commerce.catalog.readonly"
    ].joined(separator: "%20")

    // MARK: - Marketplace Insights (sold listings search)
    static let ebayBrowseAPIURL = "\(ebayBaseURL)/buy/browse/v1"
    static let ebayMarketplaceInsightsURL = "\(ebayBaseURL)/buy/marketplace_insights/v1_beta"
    static let ebaySellInventoryURL = "\(ebayBaseURL)/sell/inventory/v1"
    static let ebaySellOfferURL = "\(ebayBaseURL)/sell/account/v1"
}
