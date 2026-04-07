import SwiftUI
import Foundation

// MARK: - Identified Item (from Claude Vision)

struct IdentifiedItem: Codable, Identifiable {
    let id: UUID
    let name: String
    let brand: String?
    let category: String
    let subcategory: String?
    let description: String
    let keywords: [String]
    let confidenceScore: Double
    let suggestedCondition: ItemCondition
    let estimatedYear: String?
    let color: String?
    let size: String?
    let model: String?

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        category: String,
        subcategory: String? = nil,
        description: String,
        keywords: [String] = [],
        confidenceScore: Double = 0.95,
        suggestedCondition: ItemCondition = .good,
        estimatedYear: String? = nil,
        color: String? = nil,
        size: String? = nil,
        model: String? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.category = category
        self.subcategory = subcategory
        self.description = description
        self.keywords = keywords
        self.confidenceScore = confidenceScore
        self.suggestedCondition = suggestedCondition
        self.estimatedYear = estimatedYear
        self.color = color
        self.size = size
        self.model = model
    }
}

// MARK: - eBay Listing

struct EbayListing: Codable, Identifiable {
    let id: String
    let title: String
    let price: Double
    let currency: String
    let condition: ItemCondition
    let soldDate: Date?
    let imageURL: String?
    let listingURL: String?
    let sellerFeedback: Int?
    let shippingCost: Double?
    let isAuction: Bool
    let bidsCount: Int?

    var formattedPrice: String {
        String(format: "$%.2f", price)
    }

    var soldDateFormatted: String {
        guard let date = soldDate else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Price Analysis

struct PriceAnalysis {
    let low: Double
    let average: Double
    let high: Double
    let median: Double
    let totalSold: Int
    let samplePeriodDays: Int
    let suggestedPrice: Double
    let soldListings: [EbayListing]
    /// true = prices are asking prices from active listings, not confirmed sold prices
    var isActivePricing: Bool = false

    var priceRange: String {
        String(format: "$%.0f – $%.0f", low, high)
    }

    var formattedAverage: String {
        String(format: "$%.2f", average)
    }

    var formattedSuggested: String {
        String(format: "$%.2f", suggestedPrice)
    }
}

// MARK: - Item Condition

enum ItemCondition: String, Codable, CaseIterable {
    case newWithTags = "New with tags"
    case newWithoutTags = "New without tags"
    case newOther = "New (other)"
    case likeNew = "Like new"
    case good = "Good"
    case acceptable = "Acceptable"
    case forParts = "For parts"

    var ebayConditionId: String {
        switch self {
        case .newWithTags: return "1000"
        case .newWithoutTags: return "1500"
        case .newOther: return "1750"
        case .likeNew: return "2000"
        case .good: return "3000"
        case .acceptable: return "4000"
        case .forParts: return "7000"
        }
    }

    var color: Color {
        switch self {
        case .newWithTags, .newWithoutTags, .newOther: return Color.green
        case .likeNew: return Color.mint
        case .good: return Color.yellow
        case .acceptable: return Color.orange
        case .forParts: return Color.red
        }
    }

    var shortLabel: String {
        switch self {
        case .newWithTags, .newWithoutTags, .newOther: return "New"
        case .likeNew: return "Like New"
        case .good: return "Good"
        case .acceptable: return "Fair"
        case .forParts: return "Parts"
        }
    }
}

// MARK: - Listing Type

enum ListingType: String, CaseIterable {
    case fixedPrice = "Buy It Now"
    case auction7 = "Auction (7 days)"
    case auction3 = "Auction (3 days)"
    case auction1 = "Auction (1 day)"

    var ebayFormat: String {
        switch self {
        case .fixedPrice: return "FixedPrice"
        case .auction7, .auction3, .auction1: return "Chinese"
        }
    }

    var durationDays: Int? {
        switch self {
        case .fixedPrice: return nil
        case .auction7: return 7
        case .auction3: return 3
        case .auction1: return 1
        }
    }
}

// MARK: - Shipping Option

enum ShippingOption: String, CaseIterable {
    case uspsGround = "USPS Ground Advantage"
    case uspsFirst = "USPS First Class"
    case upGround = "UPS Ground"
    case fedexGround = "FedEx Ground"
    case free = "Free Shipping"
    case buyerPays = "Buyer pays actual"

    var estimatedCost: Double? {
        switch self {
        case .uspsGround: return 7.35
        case .uspsFirst: return 5.50
        case .upGround: return 9.50
        case .fedexGround: return 8.75
        case .free: return 0
        case .buyerPays: return nil
        }
    }

    var displayCost: String {
        guard let cost = estimatedCost else { return "Buyer pays" }
        if cost == 0 { return "Free" }
        return String(format: "$%.2f", cost)
    }
}

// MARK: - Draft Listing (user creates before posting)

struct DraftListing {
    var title: String
    var description: String
    var price: Double
    var condition: ItemCondition
    var listingType: ListingType
    var shippingOption: ShippingOption
    var category: String
    var capturedImage: UIImage?
    var identifiedItem: IdentifiedItem?

    init(from item: IdentifiedItem, suggestedPrice: Double, image: UIImage?) {
        self.title = item.name
        self.description = item.description
        self.price = suggestedPrice
        self.condition = item.suggestedCondition
        self.listingType = .fixedPrice
        self.shippingOption = .uspsGround
        self.category = item.category
        self.capturedImage = image
        self.identifiedItem = item
    }
}

// MARK: - Posted Listing Response

struct PostedListingResponse {
    let listingId: String
    let listingURL: String
    let title: String
    let price: Double
    let postedAt: Date
}

// MARK: - Scan History Entry

struct ScanHistoryEntry: Codable, Identifiable {
    let id: UUID
    let scannedAt: Date
    let itemName: String
    let brand: String?
    let category: String
    let condition: ItemCondition
    let priceLow: Double
    let priceHigh: Double
    let priceAverage: Double
    let priceSuggested: Double
    let soldListings: [EbayListing]   // capped at 5
    let thumbnailData: Data?          // compressed JPEG ~160px

    init(item: IdentifiedItem, analysis: PriceAnalysis, image: UIImage?) {
        self.id = UUID()
        self.scannedAt = Date()
        self.itemName = item.name
        self.brand = item.brand
        self.category = item.category
        self.condition = item.suggestedCondition
        self.priceLow = analysis.low
        self.priceHigh = analysis.high
        self.priceAverage = analysis.average
        self.priceSuggested = analysis.suggestedPrice
        self.soldListings = Array(analysis.soldListings.prefix(5))
        self.thumbnailData = ScanHistoryEntry.compress(image)
    }

    var thumbnail: UIImage? {
        thumbnailData.flatMap { UIImage(data: $0) }
    }

    var priceRangeFormatted: String {
        String(format: "$%.0f – $%.0f", priceLow, priceHigh)
    }

    private static func compress(_ image: UIImage?) -> Data? {
        guard let image else { return nil }
        let maxDim: CGFloat = 160
        let scale = min(maxDim / image.size.width, maxDim / image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumb = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return thumb.jpegData(compressionQuality: 0.6)
    }
}

// MARK: - Analysis Step (for UI)

enum AnalysisStep: Int, CaseIterable {
    case capturing = 0
    case identifying = 1
    case searchingEbay = 2
    case calculatingPrice = 3
    case complete = 4

    var label: String {
        switch self {
        case .capturing: return "Capturing image"
        case .identifying: return "AI visual recognition"
        case .searchingEbay: return "Searching eBay sold listings"
        case .calculatingPrice: return "Calculating price range"
        case .complete: return "Analysis complete"
        }
    }
}
