import Foundation
import UIKit

// MARK: - eBay Marketplace Service

// Isolated token store — prevents race conditions when two scans fire simultaneously.
private actor AppTokenCache {
    private var token: String?
    private var expiry: Date?

    func get() -> String? {
        guard let t = token, let e = expiry, Date() < e else { return nil }
        return t
    }

    func set(token: String, expiresIn: Int) {
        self.token = token
        self.expiry = Date().addingTimeInterval(TimeInterval(expiresIn) - 60)
    }
}

class EbayMarketplaceService {

    static let shared = EbayMarketplaceService()
    private init() {}

    private let session = URLSession.shared
    private let tokenCache = AppTokenCache()

    // MARK: - Search Sold Listings

    /// Fetch recently sold eBay listings for an identified item.
    /// Never throws — if eBay search fails or finds nothing, returns an empty
    /// PriceAnalysis so the results screen still shows the identified item.
    // Stores the last error and last scanned item so the diagnostic can use them.
    private(set) var lastSearchError: String?
    private(set) var lastScannedItem: IdentifiedItem?

    func searchSoldListings(for item: IdentifiedItem) async -> PriceAnalysis {
        lastSearchError = nil
        lastScannedItem = item
        let categoryID = ebayCategoryID(for: item.category, subcategory: item.subcategory)
        let queries = fallbackQueries(for: item)

        // Obtain an OAuth app token (Client Credentials grant).
        // If auth fails we still attempt the HTML scrape fallback.
        let token: String
        do {
            token = try await fetchAppToken()
        } catch {
            lastSearchError = "eBay auth failed: \(error.localizedDescription)"
            return await fallbackToScraping(queries: queries)
        }

        // 1. Marketplace Insights API — confirmed sold prices.
        //    Requires program approval; 403 means not yet enrolled, not a bug.
        var insightsBlocked = false
        for query in queries {
            do {
                let listings = try await fetchViaMarketplaceInsights(
                    query: query, token: token, limit: 50, categoryID: categoryID)
                if !listings.isEmpty { return buildPriceAnalysis(from: listings, isActive: false) }
            } catch EbayServiceError.apiError(let code, _) where code == 403 {
                insightsBlocked = true
                break  // Not enrolled — no point retrying other queries
            } catch {
                if lastSearchError == nil { lastSearchError = error.localizedDescription }
            }
        }
        if insightsBlocked {
            lastSearchError = "Marketplace Insights pending approval (403). Showing active listing prices."
        }

        // 2. Browse API — active listing prices (standard access, no approval needed).
        for query in queries {
            do {
                let listings = try await fetchViaBrowseAPI(
                    query: query, token: token, limit: 50, categoryID: categoryID)
                if !listings.isEmpty { return buildPriceAnalysis(from: listings, isActive: true) }
            } catch {
                // Try next query
            }
        }

        // 3. HTML scrape — last resort, no auth, real sold prices.
        return await fallbackToScraping(queries: queries)
    }

    private func fallbackToScraping(queries: [String]) async -> PriceAnalysis {
        for query in queries {
            if let listings = try? await fetchViaScraping(query: query, limit: 50),
               !listings.isEmpty {
                return buildPriceAnalysis(from: listings, isActive: false)
            }
        }
        return buildPriceAnalysis(from: [], isActive: false)
    }

    // MARK: - Private: Fallback Query Ladder

    /// Returns queries from most-specific to broadest, deduplicated.
    /// eBay is tried with each in order; the first that returns results wins.
    private func fallbackQueries(for item: IdentifiedItem) -> [String] {
        var seen = Set<String>()
        var queries: [String] = []

        func add(_ q: String) {
            let trimmed = q.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return }
            queries.append(trimmed)
        }

        // 1. Brand + model (most precise)
        if let brand = item.brand, let model = item.model {
            add("\(brand) \(model)")
        }

        // 2. Full item name as-is (Claude's clean label)
        add(item.name)

        // 3. Brand + subcategory (e.g. "Razer Mouse", not "Razer Electronics")
        if let brand = item.brand, let sub = item.subcategory {
            add("\(brand) \(sub)")
        }

        // 4. Top keywords Claude extracted
        if item.keywords.count >= 2 {
            add(item.keywords.prefix(3).joined(separator: " "))
        }

        // NOTE: bare category ("Electronics") intentionally omitted — too broad.

        return queries
    }

    /// Maps category + subcategory to an eBay category ID for search filtering.
    /// Checks subcategory first so common high-value items get a precise ID
    /// instead of the broad "Consumer Electronics" parent (which would mix in
    /// unrelated listings and corrupt the price sample).
    private func ebayCategoryID(for category: String, subcategory: String? = nil) -> String? {
        let cat = category.lowercased()
        let sub = (subcategory ?? "").lowercased()
        let combined = cat + " " + sub

        // Specific electronics subcategories — checked before the broad "electronics" bucket
        if combined.contains("phone") || combined.contains("smartphone") || combined.contains("iphone") {
            return "9355"   // Cell Phones & Smartphones
        }
        if combined.contains("console") || combined.contains("playstation") || combined.contains("xbox")
            || combined.contains("nintendo") || combined.contains("game console") {
            return "139971" // Video Game Consoles
        }
        if combined.contains("laptop") || combined.contains("macbook") || combined.contains("notebook") {
            return "177"    // Laptops & Netbooks
        }
        if combined.contains("tablet") || combined.contains("ipad") {
            return "171485" // iPads/Tablets & eBook Readers
        }
        if combined.contains("headphone") || combined.contains("earphone") || combined.contains("airpod")
            || combined.contains("earbud") || combined.contains("headset") {
            return "112529" // Portable Audio & Headphones
        }
        // Camera: only match when the subcategory is explicitly a camera body/type.
        // Exclude accessories (bags, cases, straps), dash cameras (→ Automotive),
        // and security cameras (different eBay category tree).
        if combined.contains("camera") && !combined.contains("bag") && !combined.contains("case")
            && !combined.contains("strap") && !combined.contains("accessory")
            && !combined.contains("accessories") && !combined.contains("dash")
            && !combined.contains("security") {
            return "31388"  // Digital Cameras
        }
        if combined.contains("smartwatch") || combined.contains("apple watch")
            || combined.contains("galaxy watch") {
            return "178893" // Smart Watches
        }
        // Video game software (disc, cartridge, digital code) — distinct from consoles
        if sub.contains("video game") && !sub.contains("console") {
            return "139973" // Video Games
        }
        // Musical instruments
        if combined.contains("guitar") || combined.contains("piano") || combined.contains("keyboard")
            || combined.contains("drum") || combined.contains("violin") || combined.contains("trumpet")
            || combined.contains("instrument") {
            return "619"    // Musical Instruments & Gear
        }

        // Broad category fallbacks
        switch cat {
        case let c where c.contains("sneaker") || c.contains("shoe") || c.contains("footwear"): return "15709"
        case let c where c.contains("electronic") || c.contains("tech"):                        return "293"
        case let c where c.contains("clothing") || c.contains("apparel")
                      || c.contains("shirt")    || c.contains("jacket"):                        return "11450"
        case let c where c.contains("collectible"):                                             return "1"
        case let c where c.contains("toy"):                                                     return "220"
        case let c where c.contains("game"):                                                    return "139973"
        case let c where c.contains("sport") || c.contains("outdoor"):                         return "888"
        case let c where c.contains("book") || c.contains("media"):                            return "267"
        case let c where c.contains("music") || c.contains("vinyl") || c.contains("cd"):       return "176984"
        case let c where c.contains("movie") || c.contains("dvd") || c.contains("blu-ray"):    return "617"
        case let c where c.contains("jewelry"):                                                 return "281"
        case let c where c.contains("watch"):                                                   return "14324"
        case let c where c.contains("bag") || c.contains("handbag"):                           return "169291"
        case let c where c.contains("tool") || c.contains("hardware"):                         return "631"
        case let c where c.contains("automotive") || c.contains("car") || c.contains("vehicle"): return "6028"
        case let c where c.contains("baby") || c.contains("infant"):                           return "2984"
        case let c where c.contains("health") || c.contains("beauty"):                         return "26395"
        case let c where c.contains("pet"):                                                     return "1281"
        case let c where c.contains("home") || c.contains("garden"):                           return "11700"
        case let c where c.contains("office") || c.contains("supply"):                         return "1245"
        default:                                                                                return nil
        }
    }

    // MARK: - OAuth App Token (Client Credentials grant)

    /// Returns a cached or freshly-fetched application access token.
    /// Uses Client Credentials flow — no user login required.
    private func fetchAppToken() async throws -> String {
        if let cached = await tokenCache.get() { return cached }

        let clientID     = APIConfig.ebayClientID
        let clientSecret = APIConfig.ebayClientSecret
        guard clientID != "YOUR_EBAY_CLIENT_ID",  !clientID.isEmpty,
              clientSecret != "YOUR_EBAY_CLIENT_SECRET", !clientSecret.isEmpty
        else { throw EbayServiceError.missingCredentials }

        guard let url = URL(string: APIConfig.ebayTokenURL) else {
            throw EbayServiceError.invalidURL
        }

        let raw = "\(clientID):\(clientSecret)"
        guard let encoded = raw.data(using: .utf8)?.base64EncodedString() else {
            throw EbayServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials&scope=https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope"
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EbayServiceError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw EbayServiceError.apiError(statusCode: http.statusCode, message: "Token: \(body)")
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
        }
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        await tokenCache.set(token: resp.access_token, expiresIn: resp.expires_in)
        return resp.access_token
    }

    // MARK: - Marketplace Insights API (confirmed sold prices)
    // Requires eBay program approval. Returns 403 until approved — that is
    // expected and is handled in the orchestration layer as a graceful fallback.

    private func fetchViaMarketplaceInsights(
        query: String, token: String, limit: Int, categoryID: String? = nil
    ) async throws -> [EbayListing] {
        var components = URLComponents(
            string: "\(APIConfig.ebayMarketplaceInsightsURL)/item_sales/search")!

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q",     value: query),
            URLQueryItem(name: "limit", value: String(min(limit, 200))),
        ]
        if let cat = categoryID {
            queryItems.append(URLQueryItem(name: "filter", value: "categoryIds:{\(cat)}"))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw EbayServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("EBAY_US",         forHTTPHeaderField: "X-EBAY-C-MARKETPLACE-ID")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EbayServiceError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw EbayServiceError.apiError(statusCode: http.statusCode, message: body)
        }

        guard
            let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sales = json["itemSales"] as? [[String: Any]]
        else { return [] }

        return sales.compactMap { parseInsightsItem($0) }
    }

    private func parseInsightsItem(_ item: [String: Any]) -> EbayListing? {
        guard
            let title    = item["title"] as? String,
            let priceMap = item["lastSoldPrice"] as? [String: Any],
            let priceStr = priceMap["value"] as? String,
            let price    = Double(priceStr)
        else { return nil }

        let itemID   = item["itemId"] as? String ?? UUID().uuidString
        let viewURL  = item["itemWebUrl"] as? String
        let imageURL = (item["image"] as? [String: Any])?["imageUrl"] as? String
        let soldDate = (item["lastSoldDate"] as? String)
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        let currency = priceMap["currency"] as? String ?? "USD"

        return EbayListing(
            id: itemID, title: title, price: price, currency: currency,
            condition: parseCondition(item["condition"] as? String),
            soldDate: soldDate, imageURL: imageURL, listingURL: viewURL,
            sellerFeedback: nil, shippingCost: nil, isAuction: false, bidsCount: nil
        )
    }

    // MARK: - Browse API (active listing prices, standard access)

    private func fetchViaBrowseAPI(
        query: String, token: String, limit: Int, categoryID: String? = nil
    ) async throws -> [EbayListing] {
        var components = URLComponents(
            string: "\(APIConfig.ebayBrowseAPIURL)/item_summary/search")!

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q",     value: query),
            URLQueryItem(name: "limit", value: String(min(limit, 200))),
            URLQueryItem(name: "sort",  value: "relevance"),
        ]
        if let cat = categoryID {
            queryItems.append(URLQueryItem(name: "filter", value: "categoryIds:{\(cat)}"))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw EbayServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("EBAY_US",         forHTTPHeaderField: "X-EBAY-C-MARKETPLACE-ID")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EbayServiceError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw EbayServiceError.apiError(statusCode: http.statusCode, message: body)
        }

        guard
            let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["itemSummaries"] as? [[String: Any]]
        else { return [] }

        return items.compactMap { parseBrowseItem($0) }
    }

    private func parseBrowseItem(_ item: [String: Any]) -> EbayListing? {
        guard
            let title    = item["title"] as? String,
            let priceMap = item["price"] as? [String: Any],
            let priceStr = priceMap["value"] as? String,
            let price    = Double(priceStr)
        else { return nil }

        let itemID        = item["itemId"] as? String ?? UUID().uuidString
        let viewURL       = item["itemWebUrl"] as? String
        let imageURL      = (item["image"] as? [String: Any])?["imageUrl"] as? String
        let currency      = priceMap["currency"] as? String ?? "USD"
        let feedbackScore = (item["seller"] as? [String: Any])?["feedbackScore"] as? Int
        let shippingCost  = ((item["shippingOptions"] as? [[String: Any]])?.first?["shippingCost"]
            as? [String: Any])?["value"].flatMap { Double("\($0)") }
        let isAuction     = (item["buyingOptions"] as? [String])?.contains("AUCTION") ?? false

        return EbayListing(
            id: itemID, title: title, price: price, currency: currency,
            condition: parseCondition(item["condition"] as? String),
            soldDate: nil,  // active listing — no sold date yet
            imageURL: imageURL, listingURL: viewURL,
            sellerFeedback: feedbackScore, shippingCost: shippingCost,
            isAuction: isAuction, bidsCount: nil
        )
    }

    // MARK: - HTML Scrape Fallback

    private func fetchViaScraping(query: String, limit: Int) async throws -> [EbayListing] {
        var components = URLComponents(string: "https://www.ebay.com/sch/i.html")!
        components.queryItems = [
            URLQueryItem(name: "_nkw",         value: query),
            URLQueryItem(name: "LH_Sold",      value: "1"),
            URLQueryItem(name: "LH_Complete",  value: "1"),
            URLQueryItem(name: "_sop",         value: "13"),
            URLQueryItem(name: "_ipg",         value: "50"),
        ]
        guard let url = components.url else { throw EbayServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.ebay.com", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EbayServiceError.invalidResponse
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw EbayServiceError.invalidResponse
        }
        return Array(parseEbayHTML(html).prefix(limit))
    }

    // MARK: - HTML Parsing

    private func parseEbayHTML(_ html: String) -> [EbayListing] {
        var listings: [EbayListing] = []

        // Split on list items — handle both quote styles and extra classes
        let chunks = html.components(separatedBy: "<li class=\"s-item")

        for chunk in chunks.dropFirst() {
            guard !chunk.contains("s-item__placeholder"),
                  !chunk.contains("s-item__dsa-on-bottom")
            else { continue }

            // Title — try multiple patterns eBay has used across versions
            let rawTitle: String? =
                scrape(#"class="s-item__title[^"]*"[^>]*><span[^>]*>([^<]+?)</span>"#, in: chunk)
                ?? scrape(#"class="s-item__title[^"]*"[^>]*>([^<]+?)</[^>]+>"#, in: chunk)
                ?? scrape(#"role="heading"[^>]*>([^<]+?)</[^>]+>"#, in: chunk)

            guard let rawTitle,
                  !rawTitle.trimmingCharacters(in: .whitespaces).isEmpty,
                  rawTitle != "Shop on eBay"
            else { continue }

            // Price — extract the dollar amount directly to handle spans inside spans
            let priceRaw: String? =
                scrape(#"class="s-item__price"[^>]*>[\s\S]*?\$\s*([0-9][0-9,]*\.?[0-9]*)"#, in: chunk)
                ?? scrape(#"class="s-item__price"[^>]*>([^<]+?)</span>"#, in: chunk)

            guard let priceRaw, let price = parsePrice(priceRaw) else { continue }

            let id         = scrape(#"ebay\.com/itm/(\d+)"#, in: chunk) ?? UUID().uuidString
            let listingURL = scrape(#"href="(https://www\.ebay\.com/itm/[^"?]+)"#, in: chunk)
            let imageURL   = scrape(#"src="(https://i\.ebayimg\.com[^"]+)""#, in: chunk)
                          ?? scrape(#"data-src="(https://i\.ebayimg\.com[^"]+)""#, in: chunk)

            let conditionRaw = scrape(#"class="SECONDARY_INFO"[^>]*>([^<]+?)</span>"#, in: chunk)
                            ?? scrape(#"class="s-item__subtitle"[^>]*>([^<]+?)</span>"#, in: chunk)
            let condition = parseCondition(conditionRaw)

            // Sold date — "Sold  Dec 15, 2024" or "Sold Dec 2024"
            let soldRaw = scrape(#"[Ss]old\s{1,3}([A-Z][a-z]{2}\s+\d{1,2},?\s+\d{4})"#, in: chunk)
                       ?? scrape(#"class="POSITIVE"[^>]*>[Ss]old\s+([^<]+?)</span>"#, in: chunk)
            let soldDate = parseSoldDate(soldRaw)

            listings.append(EbayListing(
                id: id,
                title: decodeHTMLEntities(rawTitle.trimmingCharacters(in: .whitespaces)),
                price: price,
                currency: "USD",
                condition: condition,
                soldDate: soldDate,
                imageURL: imageURL,
                listingURL: listingURL,
                sellerFeedback: nil,
                shippingCost: nil,
                isAuction: chunk.contains("s-item__bids"),
                bidsCount: nil
            ))
        }

        return listings
    }

    // MARK: - Parsing Helpers

    /// Returns the first capture group match for `pattern` in `string`.
    private func scrape(_ pattern: String, in string: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string)
        else { return nil }
        return String(string[range])
    }

    /// Parses "$85.00", "85.00", or "$10.00 to $20.00" — returns the lower bound.
    private func parsePrice(_ raw: String) -> Double? {
        let lower = raw.components(separatedBy: " to ").first ?? raw
        // Strip everything except digits, commas, and decimal point
        let digits = lower
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let value = Double(digits), value > 0 else { return nil }
        return value
    }

    private func parseCondition(_ raw: String?) -> ItemCondition {
        let cleaned = raw?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""

        // Exact matches first (eBay HTML scrape and Browse API condition strings)
        switch cleaned {
        case "new", "brand new", "new with tags":             return .newWithTags
        case "new without tags":                              return .newWithoutTags
        case "like new", "open box":                          return .likeNew
        case "very good", "good":                             return .good
        case "acceptable", "fair":                            return .acceptable
        case "for parts or not working", "for parts":         return .forParts
        case "pre-owned", "preowned", "used":                 return .good
        case "seller refurbished", "manufacturer refurbished",
             "certified refurbished", "refurbished":          return .likeNew
        default: break
        }

        // Substring fallback — handles variants like "New (other)", "Used – Very Good"
        if cleaned.hasPrefix("new") { return .newWithTags }
        if cleaned.contains("refurb") { return .likeNew }
        if cleaned.contains("pre-own") || cleaned.contains("preown") { return .good }
        if cleaned.contains("part") { return .forParts }

        return .good
    }

    private func parseSoldDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")

        // Full-date formats (require year to avoid wrong-century timestamps)
        for format in ["MMM d, yyyy", "MMM dd, yyyy", "d MMM yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }

        // Month+day only — eBay sometimes omits the year for current-year sales.
        // Attach the current calendar year so the date is usable for recency filtering.
        for format in ["MMM d", "MMM dd"] {
            formatter.dateFormat = format
            if let partial = formatter.date(from: raw) {
                let year = Calendar.current.component(.year, from: Date())
                return Calendar.current.date(bySetting: .year, value: year, of: partial)
            }
        }

        return nil
    }

    /// Replaces common HTML entities so titles render correctly.
    private func decodeHTMLEntities(_ string: String) -> String {
        // Named entities
        var s = string
            .replacingOccurrences(of: "&amp;",   with: "&")
            .replacingOccurrences(of: "&quot;",  with: "\"")
            .replacingOccurrences(of: "&apos;",  with: "'")
            .replacingOccurrences(of: "&lt;",    with: "<")
            .replacingOccurrences(of: "&gt;",    with: ">")
            .replacingOccurrences(of: "&nbsp;",  with: " ")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&rsquo;", with: "'")
            .replacingOccurrences(of: "&lsquo;", with: "'")
            .replacingOccurrences(of: "&rdquo;", with: "\"")
            .replacingOccurrences(of: "&ldquo;", with: "\"")
        // Numeric decimal entities: &#39; &#160; &#8217; etc.
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let matches = regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
            for match in matches.reversed() {
                guard let r = Range(match.range, in: s),
                      let numR = Range(match.range(at: 1), in: s),
                      let code = UInt32(s[numR]),
                      let scalar = Unicode.Scalar(code)
                else { continue }
                s.replaceSubrange(r, with: String(scalar))
            }
        }
        // Numeric hex entities: &#x27; &#xA0; etc.
        if let regex = try? NSRegularExpression(pattern: "&#x([0-9A-Fa-f]+);") {
            let matches = regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
            for match in matches.reversed() {
                guard let r = Range(match.range, in: s),
                      let hexR = Range(match.range(at: 1), in: s),
                      let code = UInt32(s[hexR], radix: 16),
                      let scalar = Unicode.Scalar(code)
                else { continue }
                s.replaceSubrange(r, with: String(scalar))
            }
        }
        return s
    }

    // MARK: - Price Analysis

    private func buildPriceAnalysis(from listings: [EbayListing], isActive: Bool = false) -> PriceAnalysis {
        // 1. Exclude sellers with a known feedback score below 50.
        //    Listings without a score (Insights API, scrape) are kept as-is.
        let qualified = listings.filter { $0.sellerFeedback == nil || $0.sellerFeedback! >= 50 }

        // 2. Remove price outliers via IQR (Tukey fences: Q1 - 1.5×IQR … Q3 + 1.5×IQR).
        //    Requires at least 4 data points; otherwise skip outlier removal.
        let deduped: [EbayListing]
        if qualified.count >= 4 {
            let sorted = qualified.map { $0.price }.sorted()
            let q1 = sorted[sorted.count / 4]
            let q3 = sorted[(sorted.count * 3) / 4]
            let iqr = q3 - q1
            let lower = q1 - 1.5 * iqr
            let upper = q3 + 1.5 * iqr
            deduped = qualified.filter { $0.price >= lower && $0.price <= upper }
        } else {
            deduped = qualified
        }

        // 3. Sort by price ascending for display.
        let listings = deduped.sorted { $0.price < $1.price }

        guard !listings.isEmpty else {
            return PriceAnalysis(
                low: 0, average: 0, high: 0, median: 0,
                totalSold: 0, samplePeriodDays: 90,
                suggestedPrice: 0, soldListings: [],
                isActivePricing: false
            )
        }

        let prices = listings.map { $0.price }.sorted()
        let low    = prices.first ?? 0
        let high   = prices.last  ?? 0
        let average = prices.reduce(0, +) / Double(prices.count)

        let mid    = prices.count / 2
        let median = prices.count % 2 == 0
            ? (prices[mid - 1] + prices[mid]) / 2
            : prices[mid]

        // For active listings, suggest 10% below median asking price;
        // for sold listings, suggest 8% below confirmed sale median.
        let discount = isActive ? 0.90 : 0.92
        let suggestedPrice = (median * discount).rounded(.toNearestOrAwayFromZero)

        return PriceAnalysis(
            low: low,
            average: average,
            high: high,
            median: median,
            totalSold: listings.count,
            samplePeriodDays: 90,
            suggestedPrice: suggestedPrice,
            soldListings: listings,
            isActivePricing: isActive
        )
    }

    // MARK: - Debug Diagnostic

    /// Runs a 4-step eBay API diagnostic and returns a formatted report string.
    /// Safe to call from any Task; never throws.
    func runDiagnostic(lastItem: IdentifiedItem? = nil) async -> String {
        var lines: [String] = []
        let separator = String(repeating: "─", count: 48)

        // ── Step 1: App ID & credentials ──────────────────────────
        lines.append("╔══ STEP 1 · Credentials ══╗")
        let appID = APIConfig.ebayClientID
        let hasID = appID != "YOUR_EBAY_CLIENT_ID" && !appID.isEmpty
        let isSandbox = hasID && appID.uppercased().contains("-SBX-")
        let isProd    = hasID && appID.uppercased().contains("-PRD-")

        if !hasID {
            lines.append("App ID   : NOT SET")
        } else {
            // Redact middle of key, show first 12 chars + last 4
            let visible = appID.count > 16
                ? String(appID.prefix(12)) + "…" + String(appID.suffix(4))
                : appID
            lines.append("App ID   : \(visible)")
        }
        lines.append("Type     : \(isSandbox ? "SANDBOX ⚠️" : isProd ? "PRODUCTION ✅" : hasID ? "UNKNOWN FORMAT" : "MISSING ❌")")
        lines.append("Endpoint : \(isSandbox ? "svcs.sandbox.ebay.com" : "svcs.ebay.com")")
        lines.append(separator)

        // ── Step 2: Queries that would be generated ───────────────
        lines.append("╔══ STEP 2 · Search Queries ══╗")
        if let item = lastItem {
            lines.append("Item name : \(item.name)")
            lines.append("Brand     : \(item.brand ?? "nil")")
            lines.append("Model     : \(item.model ?? "nil")")
            lines.append("Category  : \(item.category)")
            lines.append("Subcategory: \(item.subcategory ?? "nil")")
            lines.append("Keywords  : \(item.keywords.prefix(5).joined(separator: ", "))")
            lines.append("")
            let queries = fallbackQueries(for: item)
            lines.append("Generated \(queries.count) query/queries:")
            for (i, q) in queries.enumerated() {
                lines.append("  Q\(i + 1): \"\(q)\"")
            }
        } else {
            lines.append("(No item scanned yet — scan something first)")
        }
        lines.append(separator)

        // ── Step 3: Token + Browse API test call ─────────────────
        lines.append("╔══ STEP 3 · OAuth Token + Browse API Test (\"book\") ══╗")
        guard hasID else {
            lines.append("SKIPPED — no App ID configured")
            lines.append(separator)
            lines.append("╔══ STEP 4 · Diagnosis ══╗")
            lines.append("❌ No eBay App ID set. Go to Profile → eBay API Credentials.")
            return lines.joined(separator: "\n")
        }

        // Step 3a — fetch app token
        var tokenStatus = 0
        var tokenError = ""
        var diagToken = ""
        do {
            diagToken = try await fetchAppToken()
            tokenStatus = 200
            lines.append("Token endpoint : \(APIConfig.ebayTokenURL)")
            lines.append("Token result   : ✅ obtained (\(diagToken.prefix(12))…)")
        } catch {
            tokenError = error.localizedDescription
            lines.append("Token endpoint : \(APIConfig.ebayTokenURL)")
            lines.append("Token result   : ❌ \(tokenError)")
        }
        lines.append("")

        // Step 3b — Browse API search for "book"
        var browseStatus = 0
        var rawJSON = ""
        var totalResults = -1

        if !diagToken.isEmpty {
            var components = URLComponents(string: "\(APIConfig.ebayBrowseAPIURL)/item_summary/search")!
            components.queryItems = [
                URLQueryItem(name: "q",     value: "book"),
                URLQueryItem(name: "limit", value: "3"),
            ]
            if let testURL = components.url {
                lines.append("Browse API URL : \(testURL.absoluteString)")
                lines.append("Headers        : Authorization: Bearer <redacted>, X-EBAY-C-MARKETPLACE-ID: EBAY_US")
                var req = URLRequest(url: testURL)
                req.setValue("Bearer \(diagToken)", forHTTPHeaderField: "Authorization")
                req.setValue("EBAY_US",             forHTTPHeaderField: "X-EBAY-C-MARKETPLACE-ID")
                do {
                    let (data, response) = try await session.data(for: req)
                    browseStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
                    rawJSON = String(data: data, encoding: .utf8) ?? "<binary>"
                    if let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let items = json["itemSummaries"] as? [[String: Any]] {
                        totalResults = items.count
                    } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let total = json["total"] as? Int {
                        totalResults = total
                    }
                } catch {
                    rawJSON = "REQUEST FAILED: \(error.localizedDescription)"
                }
            }
        } else {
            lines.append("Browse API test: SKIPPED — token unavailable")
        }

        lines.append("HTTP Status    : \(browseStatus == 0 ? (diagToken.isEmpty ? "SKIPPED" : "ERROR") : "\(browseStatus)")")
        lines.append("Items returned : \(totalResults == -1 ? "could not parse" : "\(totalResults)")")
        lines.append("")
        let truncated = rawJSON.count > 800 ? String(rawJSON.prefix(800)) + "\n… (truncated)" : rawJSON
        if !rawJSON.isEmpty { lines.append("Raw JSON:\n\(truncated)") }
        lines.append(separator)

        // ── Step 4: Diagnosis ─────────────────────────────────────
        lines.append("╔══ STEP 4 · Diagnosis ══╗")
        if tokenStatus == 0 {
            lines.append("❌ OAuth token fetch failed.")
            lines.append("   Error: \(tokenError)")
            if tokenError.contains("401") || tokenError.contains("403") {
                lines.append("   → Client ID or Client Secret is wrong.")
                lines.append("   → Verify both in Profile → eBay API Credentials.")
            } else {
                lines.append("   → Check device internet connection.")
            }
        } else if browseStatus == 0 {
            lines.append("❌ Network error on Browse API call.")
            lines.append("   Token is valid but request never completed.")
        } else if browseStatus == 403 {
            lines.append("⚠️  Browse API returned 403.")
            lines.append("   Your production App ID may not have Browse API scope enabled.")
            lines.append("   → In eBay Developer Portal, ensure your app has")
            lines.append("     'https://api.ebay.com/oauth/api_scope' enabled.")
        } else if browseStatus == 401 {
            lines.append("❌ Browse API 401 — token was rejected.")
            lines.append("   → Try clearing credentials and re-entering them.")
        } else if browseStatus == 200 && totalResults == 0 {
            lines.append("⚠️  Browse API returned 200 but 0 items for \"book\".")
            lines.append("   This is unusual for production. Check marketplace filter.")
        } else if browseStatus == 200 && totalResults > 0 {
            lines.append("✅ Browse API working — \(totalResults) results for \"book\".")
            if let item = lastItem {
                let queries = fallbackQueries(for: item)
                lines.append("   Specific item searches still returned nothing.")
                lines.append("   Queries tried: \(queries.map { "\"\($0)\"" }.joined(separator: ", "))")
                lines.append("   → Try rescanning so Claude generates a shorter/broader item name.")
            } else {
                lines.append("   Scan an item and re-run this diagnostic for query analysis.")
            }
            lines.append("")
            lines.append("   Marketplace Insights (sold data) status:")
            lines.append("   If you see 403 in production logs for Insights API,")
            lines.append("   apply at: developer.ebay.com → My APIs → Marketplace Insights")
            lines.append("   Until approved, the app shows active listing prices instead.")
        } else {
            lines.append("HTTP \(browseStatus) — unexpected status. See raw JSON above.")
        }

        let report = lines.joined(separator: "\n")
        print("\n[SnapSell eBay Diagnostic]\n\(report)\n")
        return report
    }
}

// MARK: - eBay Listing Service

class EbayListingService {

    static let shared = EbayListingService()
    private init() {}

    private let session = URLSession.shared

    func publishListing(_ draft: DraftListing) async throws -> PostedListingResponse {
        let token = try await EbayAuthService.shared.currentToken

        let photoURL = try await uploadPhoto(draft.capturedImage, token: token)

        let sku = "SNAPSELL-\(UUID().uuidString.prefix(8).uppercased())"
        try await createInventoryItem(draft: draft, sku: sku, photoURL: photoURL, token: token)

        let offerId = try await createOffer(draft: draft, sku: sku, token: token)

        let listingId = try await publishOffer(offerId: offerId, token: token)

        let listingURL = APIConfig.useSandbox
            ? "https://www.sandbox.ebay.com/itm/\(listingId)"
            : "https://www.ebay.com/itm/\(listingId)"

        return PostedListingResponse(
            listingId: listingId,
            listingURL: listingURL,
            title: draft.title,
            price: draft.price,
            postedAt: Date()
        )
    }

    // MARK: - Step 1: Upload Photo

    private func uploadPhoto(_ image: UIImage?, token: String) async throws -> String? {
        guard let image, let imageData = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }

        guard let url = URL(string: "\(APIConfig.ebaySellInventoryURL)/media/upload") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        struct MediaResponse: Codable {
            let imageUrl: String?
        }
        let decoded = try? JSONDecoder().decode(MediaResponse.self, from: data)
        return decoded?.imageUrl
    }

    // MARK: - Step 2: Create Inventory Item

    private func createInventoryItem(
        draft: DraftListing, sku: String, photoURL: String?, token: String
    ) async throws {
        guard let url = URL(string: "\(APIConfig.ebaySellInventoryURL)/inventory_item/\(sku)") else {
            throw EbayListingError.invalidURL
        }

        var imageUrls: [[String: String]] = []
        if let photoURL {
            imageUrls = [["imageUrl": photoURL]]
        }

        let body: [String: Any] = [
            "availability": [
                "shipToLocationAvailability": ["quantity": 1]
            ],
            "condition": draft.condition.ebayConditionId,
            "conditionDescription": draft.description,
            "product": [
                "title": draft.title,
                "description": draft.description,
                "aspects": buildAspects(from: draft),
                "imageUrls": imageUrls
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 204
        else {
            throw EbayListingError.inventoryItemFailed
        }
    }

    // MARK: - Step 3: Create Offer

    private func createOffer(draft: DraftListing, sku: String, token: String) async throws -> String {
        guard let url = URL(string: "\(APIConfig.ebaySellInventoryURL)/offer") else {
            throw EbayListingError.invalidURL
        }

        var pricingDetails: [String: Any]
        if draft.listingType == .fixedPrice {
            pricingDetails = [
                "price": ["value": String(format: "%.2f", draft.price), "currency": "USD"]
            ]
        } else {
            pricingDetails = [
                "auctionStartPrice": ["value": String(format: "%.2f", draft.price * 0.5), "currency": "USD"],
                "auctionReservePrice": ["value": String(format: "%.2f", draft.price), "currency": "USD"]
            ]
        }

        let shippingServiceCode: String
        switch draft.shippingOption {
        case .uspsGround: shippingServiceCode = "USPSGroundAdvantage"
        case .uspsFirst: shippingServiceCode = "USPSFirstClass"
        case .upGround: shippingServiceCode = "UPS_GROUND"
        case .fedexGround: shippingServiceCode = "FedEx_Ground"
        case .free: shippingServiceCode = "USPSGroundAdvantage"
        case .buyerPays: shippingServiceCode = "USPSGroundAdvantage"
        }

        let shippingCost = draft.shippingOption == .free
            ? "0.00"
            : String(format: "%.2f", draft.shippingOption.estimatedCost ?? 0)

        let body: [String: Any] = [
            "sku": sku,
            "marketplaceId": "EBAY_US",
            "format": draft.listingType.ebayFormat,
            "listingDuration": draft.listingType.durationDays.map { "DAYS_\($0)" } ?? "GTC",
            "pricingSummary": pricingDetails,
            "listingPolicies": [
                "fulfillmentPolicyId": "YOUR_FULFILLMENT_POLICY_ID",
                "paymentPolicyId": "YOUR_PAYMENT_POLICY_ID",
                "returnPolicyId": "YOUR_RETURN_POLICY_ID"
            ],
            "categoryId": ebayCategory(for: draft.category, subcategory: draft.identifiedItem?.subcategory),
            "shippingOptions": [
                [
                    "optionType": "DOMESTIC",
                    "costType": "FLAT_RATE",
                    "shippingServices": [
                        [
                            "shippingServiceCode": shippingServiceCode,
                            "shippingCost": ["value": shippingCost, "currency": "USD"]
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EbayListingError.offerCreationFailed
        }

        struct OfferResponse: Codable {
            let offerId: String?
        }
        let decoded = try JSONDecoder().decode(OfferResponse.self, from: data)
        guard let offerId = decoded.offerId else {
            throw EbayListingError.missingOfferId
        }
        return offerId
    }

    // MARK: - Step 4: Publish Offer

    private func publishOffer(offerId: String, token: String) async throws -> String {
        guard let url = URL(string: "\(APIConfig.ebaySellInventoryURL)/offer/\(offerId)/publish") else {
            throw EbayListingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EbayListingError.publishFailed
        }

        struct PublishResponse: Codable {
            let listingId: String?
        }
        let decoded = try JSONDecoder().decode(PublishResponse.self, from: data)
        return decoded.listingId ?? offerId
    }

    // MARK: - Helpers

    private func buildAspects(from draft: DraftListing) -> [String: [String]] {
        var aspects: [String: [String]] = [:]
        if let item = draft.identifiedItem {
            if let brand = item.brand { aspects["Brand"] = [brand] }
            if let size = item.size { aspects["Size"] = [size] }
            if let color = item.color { aspects["Color"] = [color] }
            if let model = item.model { aspects["Model"] = [model] }
            if let year = item.estimatedYear { aspects["Year"] = [year] }
        }
        return aspects
    }

    private func ebayCategory(for category: String, subcategory: String? = nil) -> String {
        let cat = category.lowercased()
        let sub = (subcategory ?? "").lowercased()
        let combined = cat + " " + sub

        if combined.contains("phone") || combined.contains("smartphone") || combined.contains("iphone") {
            return "9355"
        }
        if combined.contains("console") || combined.contains("playstation") || combined.contains("xbox")
            || combined.contains("nintendo") || combined.contains("game console") {
            return "139971"
        }
        if combined.contains("laptop") || combined.contains("macbook") || combined.contains("notebook") {
            return "177"
        }
        if combined.contains("tablet") || combined.contains("ipad") {
            return "171485"
        }
        if combined.contains("headphone") || combined.contains("earphone") || combined.contains("airpod")
            || combined.contains("earbud") || combined.contains("headset") {
            return "112529"
        }
        if combined.contains("camera") && !combined.contains("bag") && !combined.contains("case")
            && !combined.contains("strap") && !combined.contains("accessory")
            && !combined.contains("dash") && !combined.contains("security") {
            return "31388"
        }
        if combined.contains("smartwatch") || combined.contains("apple watch")
            || combined.contains("galaxy watch") {
            return "178893"
        }
        if sub.contains("video game") && !sub.contains("console") { return "139973" }
        if combined.contains("guitar") || combined.contains("piano") || combined.contains("keyboard")
            || combined.contains("drum") || combined.contains("instrument") {
            return "619"
        }

        switch cat {
        case let c where c.contains("sneaker") || c.contains("shoe"):        return "15709"
        case let c where c.contains("electronic") || c.contains("tech"):     return "293"
        case let c where c.contains("clothing") || c.contains("apparel"):    return "11450"
        case let c where c.contains("collectible"):                          return "1"
        case let c where c.contains("toy"):                                  return "220"
        case let c where c.contains("game"):                                 return "139973"
        case let c where c.contains("sport") || c.contains("outdoor"):      return "888"
        case let c where c.contains("book") || c.contains("media"):         return "267"
        case let c where c.contains("music") || c.contains("vinyl"):        return "176984"
        case let c where c.contains("movie") || c.contains("dvd"):          return "617"
        case let c where c.contains("jewelry"):                             return "281"
        case let c where c.contains("watch"):                               return "14324"
        case let c where c.contains("tool") || c.contains("hardware"):      return "631"
        case let c where c.contains("automotive") || c.contains("car"):     return "6028"
        case let c where c.contains("baby"):                                return "2984"
        case let c where c.contains("health") || c.contains("beauty"):      return "26395"
        case let c where c.contains("pet"):                                 return "1281"
        case let c where c.contains("home") || c.contains("garden"):        return "11700"
        default:                                                              return "99"
        }
    }
}

// MARK: - Errors

enum EbayServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noResults
    case unauthorized
    case missingCredentials
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Invalid eBay URL."
        case .invalidResponse:    return "Could not reach eBay. Check your connection."
        case .noResults:          return "No listings found for this item."
        case .unauthorized:       return "eBay token expired. Please sign in again."
        case .missingCredentials: return "eBay credentials not set. Go to Profile → eBay API Credentials."
        case .apiError(let code, let msg): return "eBay \(code): \(msg)"
        }
    }
}

enum EbayListingError: LocalizedError {
    case invalidURL
    case inventoryItemFailed
    case offerCreationFailed
    case missingOfferId
    case publishFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid listing URL."
        case .inventoryItemFailed: return "Failed to create inventory item."
        case .offerCreationFailed: return "Failed to create eBay offer."
        case .missingOfferId: return "Missing offer ID from eBay."
        case .publishFailed: return "Failed to publish listing."
        }
    }
}
