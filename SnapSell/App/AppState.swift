import SwiftUI
import Combine

enum AppTab {
    case scan, listings, sold, profile
}

class AppState: ObservableObject {
    @Published var activeTab: AppTab = .scan
    @Published var myListings: [EbayListing] = []
    @Published var soldItems: [EbayListing] = []
    @Published var scanHistory: [ScanHistoryEntry] = []

    private let historyKey = "scanHistory"

    init() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([ScanHistoryEntry].self, from: data) {
            scanHistory = saved
        }
    }

    func appendScanHistory(_ entry: ScanHistoryEntry) {
        scanHistory.insert(entry, at: 0)
        if let data = try? JSONEncoder().encode(scanHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
}
