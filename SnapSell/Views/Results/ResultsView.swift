import SwiftUI

struct ResultsView: View {
    let item: IdentifiedItem
    let priceAnalysis: PriceAnalysis
    let capturedImage: UIImage
    let onListTap: () -> Void
    let onRescan: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                headerSection
                    .background(Color(UIColor.systemBackground))

                // Listings
                listingsSection
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().opacity(0.15)
                Button(action: onListTap) {
                    HStack(spacing: 10) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 17))
                        Text("List on eBay")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color("AccentYellow"), in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .background(.ultraThinMaterial)
            .padding(.bottom, 49) // clears custom tab bar (49pt) above system safe area
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onRescan) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16))
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            // Item identity row
            HStack(alignment: .top, spacing: 14) {
                // Captured photo thumbnail
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let brand = item.brand {
                        Text(brand + (item.model != nil ? " · \(item.model!)" : ""))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    // Confidence badge
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                        Text("\(Int(item.confidenceScore * 100))% match")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(.green.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(.green.opacity(0.3), lineWidth: 0.5))
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(item.keywords, id: \.self) { keyword in
                        Text(keyword)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 12)
                            .background(Color(.systemGray6), in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)

            Divider().padding(.horizontal, 20)

            // Price summary
            VStack(alignment: .leading, spacing: 10) {
                Text(priceAnalysis.isActivePricing
                    ? "Current listings (asking price) · \(priceAnalysis.totalSold) listings"
                    : "Sold in last 90 days · \(priceAnalysis.totalSold) listings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
                    .textCase(.uppercase)
                    .padding(.top, 16)

                HStack(spacing: 12) {
                    PriceStat(label: "Low", value: priceAnalysis.low)
                    Divider().frame(height: 36)
                    PriceStat(label: "Avg", value: priceAnalysis.average, highlighted: true)
                    Divider().frame(height: 36)
                    PriceStat(label: "High", value: priceAnalysis.high)
                    Divider().frame(height: 36)
                    PriceStat(label: "Suggested", value: priceAnalysis.suggestedPrice, accent: true)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)

            Divider()
        }
    }

    // MARK: - Listings

    private var listingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(priceAnalysis.isActivePricing ? "Current listings" : "Recent sold listings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(1)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            if priceAnalysis.soldListings.isEmpty {
                noListingsPlaceholder
            } else {
                ForEach(priceAnalysis.soldListings) { listing in
                    ListingRow(listing: listing)
                    Divider().padding(.leading, 84)
                }
            }
        }
    }

    private var noListingsPlaceholder: some View {
        let ebayError = EbayMarketplaceService.shared.lastSearchError

        return VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No sold listings found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            if let msg = ebayError {
                Text(msg)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Text("Enter your Production App ID in\nProfile → eBay Developer for price data.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Price Stat

struct PriceStat: View {
    let label: String
    let value: Double
    var highlighted = false
    var accent = false

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            Text(String(format: "$%.0f", value))
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(accent ? Color("AccentYellow") : (highlighted ? .primary : .secondary))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Listing Row

struct ListingRow: View {
    let listing: EbayListing

    var body: some View {
        HStack(spacing: 12) {
            // Listing image
            AsyncImage(url: URL(string: listing.imageURL ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(.systemGray5)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(listing.title)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(listing.formattedPrice)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)

                    Text(listing.soldDateFormatted)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    ConditionBadge(condition: listing.condition)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if let urlStr = listing.listingURL, let url = URL(string: urlStr) {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Condition Badge

struct ConditionBadge: View {
    let condition: ItemCondition

    var body: some View {
        Text(condition.shortLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(condition.color)
            .padding(.vertical, 2)
            .padding(.horizontal, 7)
            .background(condition.color.opacity(0.12), in: Capsule())
    }
}
