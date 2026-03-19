import SwiftUI
import Combine

enum AppTab {
    case scan, listings, sold, profile
}

class AppState: ObservableObject {
    @Published var activeTab: AppTab = .scan
    @Published var myListings: [EbayListing] = []
    @Published var soldItems: [EbayListing] = []
}
