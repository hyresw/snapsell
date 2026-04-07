import SwiftUI

struct MyListingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSegment = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    Text("Active").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if selectedSegment == 0 {
                    activeListingsContent
                } else {
                    ScanHistoryView()
                }
            }
            .navigationTitle("My Listings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    private var activeListingsContent: some View {
        if appState.myListings.isEmpty {
            EmptyStateView(
                icon: "shippingbox",
                title: "No listings yet",
                subtitle: "Scan an item and list it on eBay to see it here."
            )
        } else {
            List(appState.myListings) { listing in
                ActiveListingRow(listing: listing)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .listStyle(.plain)
        }
    }
}

struct ActiveListingRow: View {
    let listing: EbayListing

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            AsyncImage(url: URL(string: listing.imageURL ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color(.systemGray5)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(listing.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(listing.formattedPrice)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color("AccentYellow"))

                    Text("Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 7)
                        .background(.green.opacity(0.12), in: Capsule())
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Scan History

struct ScanHistoryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.scanHistory.isEmpty {
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: "No scan history",
                subtitle: "Items you scan will appear here with their eBay price data."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(appState.scanHistory) { entry in
                        ScanHistoryCard(entry: entry)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}

struct ScanHistoryCard: View {
    let entry: ScanHistoryEntry
    @State private var expanded = false

    private var scannedDateFormatted: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: entry.scannedAt, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row ──────────────────────────────────────────────
            HStack(spacing: 12) {
                // Thumbnail
                Group {
                    if let img = entry.thumbnail {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.systemGray5)
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.itemName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    if let brand = entry.brand {
                        Text(brand)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Text(entry.priceRangeFormatted)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color("AccentYellow"))

                        Text(entry.condition.shortLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(entry.condition.color)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(entry.condition.color.opacity(0.12), in: Capsule())
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(scannedDateFormatted)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    if !entry.soldListings.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                        } label: {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color("AccentYellow"))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)

            // ── eBay snapshot (non-interactive) ─────────────────────────
            if expanded && !entry.soldListings.isEmpty {
                VStack(spacing: 0) {
                    Divider().padding(.horizontal, 14)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("eBay Snapshot · \(entry.soldListings.count) comparable listings")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)

                        VStack(spacing: 6) {
                            ForEach(entry.soldListings) { listing in
                                EbaySnapshotRow(listing: listing)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct EbaySnapshotRow: View {
    let listing: EbayListing

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: listing.imageURL ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color(.systemGray5)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                Text(listing.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(listing.soldDateFormatted)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(listing.formattedPrice)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .allowsHitTesting(false)
    }
}

// MARK: - Sold View

struct SoldView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "dollarsign.circle",
                title: "No sales yet",
                subtitle: "Sold items will appear here when buyers purchase your listings."
            )
            .navigationTitle("Sold")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Color("AccentYellow").opacity(0.7))
                .padding(.bottom, 8)

            Text(title)
                .font(.system(size: 20, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
