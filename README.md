# SnapSell — iOS Reselling App

Snap a photo of any item → AI identifies it → See real eBay sold prices → List it in one tap.

Supports two AI backends: **Claude (cloud)** via the Anthropic API, or a **local vision LLM** (Ollama / LM Studio) for fully offline identification.

---

## Architecture Overview

```
SnapSell/
├── App/
│   ├── SnapSellApp.swift            # @main entry point
│   ├── AppState.swift               # Global ObservableObject (listings, tab state)
│   └── ContentView.swift            # Root TabView
│
├── Models/
│   └── Models.swift                 # IdentifiedItem, EbayListing, PriceAnalysis,
│                                    # DraftListing, ItemCondition, ListingType, etc.
│
├── Services/
│   ├── APIConfig.swift              # All credentials + endpoint config (UserDefaults)
│   ├── VisionService.swift          # VisionServiceProtocol + routing manager
│   ├── ClaudeVisionService.swift    # Anthropic API → item identification (cloud)
│   ├── LocalLLMService.swift        # Ollama / LM Studio → item identification (local)
│   ├── EbayAuthService.swift        # OAuth 2.0 (ASWebAuthenticationSession)
│   └── EbayService.swift            # Price lookup + listing creation
│
├── Views/
│   ├── Camera/
│   │   ├── CameraManager.swift      # AVFoundation capture session
│   │   ├── ScanFlowView.swift       # Flow coordinator: camera→analyze→results→list→success
│   │   └── CameraView.swift         # Live preview + shutter UI
│   ├── Analysis/
│   │   └── AnalyzingView.swift      # Animated step-by-step analysis screen
│   ├── Results/
│   │   └── ResultsView.swift        # Identified item + sold listings + price stats
│   ├── Listing/
│   │   ├── CreateListingView.swift  # Full listing form
│   │   ├── SuccessView.swift        # Post-listing confirmation
│   │   └── MyListingsView.swift     # Active listings + scan history tabs
│   └── Profile/
│       └── ProfileView.swift        # eBay OAuth, API keys, local LLM settings
│
└── Resources/
    ├── Info.plist                   # Permissions, URL schemes, ATS config
    └── Assets.xcassets/             # AccentYellow, AppIcon
```

---

## Requirements

- **Xcode 15+**
- **iOS 17.0+** deployment target
- **Physical iPhone** (camera doesn't work in Simulator)
- **Vision backend** — choose one or both:
  - Cloud: Anthropic API key from https://console.anthropic.com
  - Local: Ollama or LM Studio running on your Mac (same Wi-Fi)
- **eBay Developer account** — https://developer.ebay.com

---

## Quick Start

### 1. Clone & Open

```bash
git clone <your-repo>
open SnapSell/SnapSell.xcodeproj
```

### 2. Set Your Team

Xcode → `SnapSell` target → `Signing & Capabilities`:
- Set **Team** to your Apple Developer account
- Update Bundle ID if needed (`com.yourcompany.snapsell`)

### 3. Configure a Vision Backend

#### Option A — Claude (cloud, default)

**At runtime (recommended for development):**
Launch the app → Profile tab → "Anthropic API Key" → paste your `sk-ant-...` key.

**Via Xcode environment variable:**
Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables:
```
ANTHROPIC_API_KEY = sk-ant-api03-...
```

**For production:** Replace `UserDefaults` reads in `APIConfig.swift` with Keychain.

#### Option B — Local LLM (offline, no API costs)

Run a vision-capable model on your Mac:

```bash
# Ollama (recommended)
brew install ollama
ollama pull gemma3:12b       # or qwen2.5vl:7b, llava:13b, moondream
ollama serve                  # starts at http://localhost:11434

# LM Studio
# Download from lmstudio.ai, load a VLM, enable the local server (port 1234)
```

In the app → Profile tab → "Local LLM" section → enable the toggle → configure URL and model.

Built-in presets:
| Preset | URL | Model |
|--------|-----|-------|
| Gemma 3 12B | http://localhost:11434/v1 | gemma3:12b |
| Gemma 3 4B | http://localhost:11434/v1 | gemma3:4b |
| Qwen2.5-VL 7B | http://localhost:11434/v1 | qwen2.5vl:7b |
| LLaVA 13B | http://localhost:11434/v1 | llava:13b |
| LM Studio | http://localhost:1234/v1 | *(model loaded in app)* |

The iPhone and Mac must be on the same Wi-Fi network.

### 4. Set Up eBay

#### a) Create an app at https://developer.ebay.com

- My Account → Application Keys → **Create a keyset**
- Start with **Sandbox**, switch to Production when ready
- Sandbox is auto-detected: if your Client ID contains `-SBX-`, all eBay URLs switch automatically

#### b) Add credentials

In-app (Profile tab) or via environment variables:
```
EBAY_CLIENT_ID     = your-client-id
EBAY_CLIENT_SECRET = your-client-secret
```

#### c) Register the OAuth redirect URI

In your eBay app's Auth settings, add:
```
snapsell://oauth/callback
```

#### d) Create Seller Business Policies

Required before the listing API will publish. In your eBay Seller Account:
1. Go to https://www.bizpolicies.ebay.com/
2. Create a **Payment**, **Return**, and **Fulfillment (shipping)** policy
3. Copy the three policy IDs into `EbayService.swift` → `createOffer()`:

```swift
"listingPolicies": [
    "fulfillmentPolicyId": "YOUR_FULFILLMENT_POLICY_ID",
    "paymentPolicyId":     "YOUR_PAYMENT_POLICY_ID",
    "returnPolicyId":      "YOUR_RETURN_POLICY_ID"
]
```

---

## How It Works

### Item Identification

```
UIImage (JPEG, max 1568px)
    → base64 encode
    → POST to active backend
    → JSON: name, brand, model, category, keywords, confidence, condition
    → IdentifiedItem model
```

`VisionServiceManager` routes to `ClaudeVisionService` (Anthropic API) or `LocalLLMService` (OpenAI-compatible `/v1/chat/completions`) based on the `localLLMEnabled` flag.

Claude uses extended thinking (5 000 budget tokens) to work through ambiguous visual details before committing to a model identification.

### eBay Price Lookup

Three-tier fallback chain:

```
1. Marketplace Insights API  → confirmed sold prices (best)
2. Browse API                → active listing prices (fallback)
3. HTML scraper              → public sold prices (last resort)
```

Outlier removal uses Tukey fences (IQR × 1.5) before computing stats. Suggested price = `median × 0.92` (8% below median for faster sell-through).

### Listing Creation

```
1. Upload photo  → POST /sell/inventory/v1/media/upload
2. Create item   → PUT  /sell/inventory/v1/inventory_item/{sku}
3. Create offer  → POST /sell/inventory/v1/offer
4. Publish       → POST /sell/inventory/v1/offer/{offerId}/publish
                 → returns live eBay listing ID
```

---

## Key Customization Points

### Price Suggestion

`EbayService.swift` → `buildPriceAnalysis()`:
```swift
let suggestedPrice = (median * 0.92).rounded()
```
Adjust the multiplier to match your sell-through preference.

### Category Mapping

`EbayService.swift` → `ebayCategoryID(for:subcategory:)` maps item categories to eBay category IDs. The mapping covers all major Walmart department equivalents. Expand with the full eBay taxonomy:
https://developer.ebay.com/devzone/xml/docs/reference/ebay/getcategories.html

### Condition Mapping

`Models.swift` → `ItemCondition.ebayConditionId` maps conditions to official eBay condition IDs. `ItemCondition.parse()` accepts both camelCase (`"newWithTags"`) and display strings (`"New with tags"`) from LLM responses.

---

## Sandbox vs Production

| | Sandbox | Production |
|---|---|---|
| Client ID | Contains `-SBX-` | Does not contain `-SBX-` |
| eBay URLs | api.sandbox.ebay.com | api.ebay.com |
| Listings posted | sandbox.ebay.com | ebay.com |
| Real money | No | Yes |
| Marketplace Insights | Limited data | Full data |

Sandbox is detected automatically from the Client ID — no manual flag to flip.

---

## Security Notes

- API keys and OAuth tokens are stored in `UserDefaults`. For production, replace with **Keychain** (`SecItemAdd` / `SecItemCopyMatching`). `APIConfig.swift` is the single file to update.
- App Transport Security (ATS) allows HTTP only for `localhost` (required for local LLM). All cloud endpoints (Anthropic, eBay) are HTTPS.
- Diagnostic logging (`runDiagnostic()`) is compiled out in Release builds (`#if DEBUG`).
- The local LLM URL is validated to be a well-formed `http` or `https` URL before use.

---

## Permissions

`Info.plist` includes:
- `NSCameraUsageDescription` — live camera capture
- `NSPhotoLibraryUsageDescription` — photo library import
- `CFBundleURLTypes` with `snapsell` scheme — eBay OAuth callback
- ATS `NSExceptionDomains` for `localhost` HTTP (local LLM only)

---

## Known Limitations & TODOs

- **Marketplace Insights API** requires separate eBay approval. Browse API fallback is enabled automatically.
- **Seller policies** (payment/return/fulfillment) must be created in Seller Hub before the listing API will publish.
- **Photo upload** to eBay's media API has separate gating; some setups use external hosting (S3, Cloudinary) with a URL passed to eBay.
- **Persistent storage**: listings are in-memory (`AppState`). Add CoreData or SwiftData for persistence across launches.
- **Multiple photos**: form has a placeholder; wire up `PHPickerViewController` for up to 12 images.
- **Barcode scanning**: add `AVCaptureMetadataOutput` to `CameraManager` for instant barcode → item lookup.
- **Keychain migration**: replace `UserDefaults` credential storage with Keychain for production.

---

## License

MIT — build and ship freely.
