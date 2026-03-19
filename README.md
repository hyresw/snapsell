# SnapSell — iOS App

Snap a photo of any item → Claude AI identifies it → See real eBay sold prices → List it with one tap.

---

## Architecture Overview

```
SnapSell/
├── App/
│   ├── SnapSellApp.swift          # @main entry point
│   ├── AppState.swift             # Global ObservableObject (listings, tab state)
│   └── ContentView.swift          # Root TabView
│
├── Models/
│   └── Models.swift               # IdentifiedItem, EbayListing, PriceAnalysis,
│                                  # DraftListing, ItemCondition, ListingType, etc.
│
├── Services/
│   ├── APIConfig.swift            # All API endpoints + credential loading
│   ├── ClaudeVisionService.swift  # Anthropic API → item identification
│   ├── EbayAuthService.swift      # OAuth 2.0 flow (ASWebAuthenticationSession)
│   └── EbayService.swift          # Marketplace Insights + Inventory/Offer APIs
│
├── Views/
│   ├── Camera/
│   │   ├── CameraManager.swift    # AVFoundation capture session
│   │   ├── ScanFlowView.swift     # Flow coordinator (camera→analyze→results→list→success)
│   │   └── CameraView.swift       # Live preview + shutter UI
│   ├── Analysis/
│   │   └── AnalyzingView.swift    # Animated step-by-step analysis screen
│   ├── Results/
│   │   └── ResultsView.swift      # Identified item + sold listings + price stats
│   ├── Listing/
│   │   ├── CreateListingView.swift # Full listing form (price, condition, shipping, etc.)
│   │   ├── SuccessView.swift       # Post-listing confirmation
│   │   └── MyListingsView.swift    # Active listings tab
│   └── Profile/
│       └── ProfileView.swift       # eBay OAuth connect + API key settings
│
└── Resources/
    ├── Info.plist                  # Camera/photo permissions, URL schemes
    └── Assets.xcassets/            # AccentYellow color, AppIcon
```

---

## Requirements

- **Xcode 15+**
- **iOS 17.0+** deployment target
- **Physical iPhone** (camera doesn't work in Simulator)
- **Anthropic API key** — get one at https://console.anthropic.com
- **eBay Developer account** — register at https://developer.ebay.com

---

## Quick Start

### 1. Clone & Open

```bash
git clone <your-repo>
open SnapSell/SnapSell.xcodeproj
```

### 2. Set Your Team

In Xcode → `SnapSell` target → `Signing & Capabilities`:
- Set **Team** to your Apple Developer account
- Bundle ID: `com.yourcompany.snapsell` (change to match your team)

### 3. Add Anthropic API Key

**Option A — At runtime (recommended for development):**
Launch the app → Profile tab → "Anthropic API Key" → paste your key.
It's stored in `UserDefaults` on device.

**Option B — Environment variable (for Xcode scheme):**
Xcode → Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables:
```
ANTHROPIC_API_KEY = sk-ant-api03-...
```

**Option C — For production**, use Keychain. Replace `UserDefaults` reads in `APIConfig.swift` with `KeychainService`.

### 4. Set Up eBay Developer Account

#### a) Register at https://developer.ebay.com

#### b) Create a new app
- Go to **My Account → Application Keys**
- Click **Create a keyset**
- App Name: `SnapSell`
- Environment: Start with **Sandbox**, switch to **Production** when ready

#### c) Get your credentials
Copy these into `APIConfig.swift` or set as environment variables:
```
EBAY_CLIENT_ID     = your-sandbox-client-id
EBAY_CLIENT_SECRET = your-sandbox-client-secret
```

#### d) Register your OAuth Redirect URI
In the eBay developer portal under your app's **Auth Accepted OAuth Scopes**:
- Add redirect URI: `snapsell://oauth/callback`
- This matches the URL scheme registered in `Info.plist`

#### e) Create Seller Business Policies (required for listing API)
In your **eBay Seller Account** (sandbox or production):
1. Go to: https://www.bizpolicies.ebay.com/
2. Create a **Payment policy** → note the `paymentPolicyId`
3. Create a **Return policy** → note the `returnPolicyId`
4. Create a **Fulfillment (shipping) policy** → note the `fulfillmentPolicyId`

Update these in `EbayService.swift` → `createOffer()`:
```swift
"listingPolicies": [
    "fulfillmentPolicyId": "YOUR_FULFILLMENT_POLICY_ID",
    "paymentPolicyId":     "YOUR_PAYMENT_POLICY_ID",
    "returnPolicyId":      "YOUR_RETURN_POLICY_ID"
]
```

#### f) Switch from Sandbox to Production
In `APIConfig.swift`:
```swift
static let useSandbox = false   // ← change this
```
And swap in your production Client ID/Secret.

---

## API Flow

### Item Identification (Claude Vision)

```
UIImage (JPEG)
    → base64 encode
    → POST /v1/messages  (claude-opus-4-5, vision)
    → Structured JSON response
    → IdentifiedItem model
```

The system prompt instructs Claude to return a strict JSON structure with name, brand, category, keywords, confidence score, condition suggestion, etc.

### eBay Sold Listings (Marketplace Insights API)

```
IdentifiedItem.keywords + brand + model
    → GET /buy/marketplace_insights/v1_beta/item_sales/search?q=...
    → Array of sold listings with prices and dates
    → PriceAnalysis (low/avg/high/median/suggested)
```

> **Note:** The Marketplace Insights API is in beta. You need to request access at:
> https://developer.ebay.com/programs/marketplace-insights

**Fallback:** If you can't access Marketplace Insights, use the **Browse API** to search active listings:
```
GET /buy/browse/v1/item_summary/search?q=...&filter=soldItems:true
```

### Listing Creation (Inventory + Offer API)

Four-step process:
```
1. Upload photo    → POST /sell/inventory/v1/media/upload
2. Create item     → PUT  /sell/inventory/v1/inventory_item/{sku}
3. Create offer    → POST /sell/inventory/v1/offer
4. Publish offer   → POST /sell/inventory/v1/offer/{offerId}/publish
                   → returns listingId (live eBay item number)
```

---

## Key Customization Points

### Category Mapping
`EbayService.swift` → `ebayCategory(for:)` maps item categories to eBay category IDs.
Expand this with the full eBay category taxonomy for better placement:
https://developer.ebay.com/devzone/xml/docs/reference/ebay/getcategories.html

### Price Suggestion Algorithm
`EbayService.swift` → `buildPriceAnalysis()`:
```swift
let suggestedPrice = (median * 0.92).rounded()
```
Currently suggests 8% below median to increase sell-through speed.
Adjust this multiplier to taste.

### Condition Mapping
`Models.swift` → `ItemCondition.ebayConditionId` maps to official eBay condition IDs.
These are category-specific on eBay; the current values work for most categories.

---

## Running in Sandbox vs Production

| Setting | Sandbox | Production |
|---|---|---|
| `useSandbox` | `true` | `false` |
| eBay app keys | Sandbox keyset | Production keyset |
| Listings posted | sandbox.ebay.com | ebay.com |
| Real money | No | Yes |
| Marketplace Insights | Limited data | Full data |

---

## Permissions Checklist

`Info.plist` already includes:
- `NSCameraUsageDescription` — camera access
- `NSPhotoLibraryUsageDescription` — photo library
- `CFBundleURLTypes` with `snapsell` scheme — OAuth callback
- App Transport Security exceptions for Anthropic + eBay APIs

---

## Known Limitations & TODOs

- **Marketplace Insights API access** requires separate eBay approval. Use Browse API as fallback.
- **Seller policies** (payment/return/fulfillment) must be pre-created in Seller Hub before listing.
- **Photo upload** to eBay's media API is gated; some apps use external image hosting (S3, Cloudinary) and pass the URL to eBay.
- **Persistent storage**: listings are in-memory (`AppState`). Add CoreData or SwiftData for persistence across launches.
- **Multiple photos**: the form has a placeholder for additional photos. Wire up `PHPickerViewController` to collect up to 12 images.
- **Barcode scanning**: add `AVCaptureMetadataOutput` to `CameraManager` for instant barcode → item lookup.
- **Push notifications**: use APNs to notify when an item sells.

---

## License

MIT — build and ship freely.
