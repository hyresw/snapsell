import SwiftUI

struct MyListingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
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
            .navigationTitle("My Listings")
            .navigationBarTitleDisplayMode(.large)
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
