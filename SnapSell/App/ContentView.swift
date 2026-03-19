import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen content — each tab fills the entire display
            Group {
                switch appState.activeTab {
                case .scan:     ScanFlowView()
                case .listings: MyListingsView()
                case .sold:     SoldView()
                case .profile:  ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            // Custom tab bar overlaid at the bottom
            CustomTabBar(activeTab: $appState.activeTab)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(Color("AccentYellow"))
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var activeTab: AppTab

    private struct TabItem {
        let tab: AppTab
        let icon: String
        let label: String
    }

    private let items: [TabItem] = [
        TabItem(tab: .scan,     icon: "camera.fill",          label: "Scan"),
        TabItem(tab: .listings, icon: "shippingbox.fill",     label: "Listings"),
        TabItem(tab: .sold,     icon: "dollarsign.circle.fill", label: "Sold"),
        TabItem(tab: .profile,  icon: "person.fill",           label: "Profile"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.label) { item in
                Button {
                    activeTab = item.tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20))
                        Text(item.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(activeTab == item.tab
                        ? Color("AccentYellow")
                        : Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 34)     // home indicator clearance
        .background(.ultraThinMaterial)
    }
}
