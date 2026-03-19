import SwiftUI

struct SuccessView: View {
    let response: PostedListingResponse
    let onScanAnother: () -> Void

    @State private var circleScale: CGFloat = 0.5
    @State private var circleOpacity: CGFloat = 0
    @State private var contentOpacity: CGFloat = 0
    @State private var contentOffset: CGFloat = 20

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Animated success icon
                ZStack {
                    Circle()
                        .fill(.green.opacity(0.12))
                        .frame(width: 120, height: 120)
                        .scaleEffect(circleScale)

                    Circle()
                        .fill(.green.opacity(0.06))
                        .frame(width: 160, height: 160)
                        .scaleEffect(circleScale * 0.9)

                    Image(systemName: "checkmark")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.green)
                        .opacity(circleOpacity)
                }
                .padding(.bottom, 36)

                // Title
                VStack(spacing: 10) {
                    Text("Listed!")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Your \(response.title) is now live on eBay")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .opacity(contentOpacity)
                .offset(y: contentOffset)
                .padding(.bottom, 32)

                // Listing details card
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Listed for")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(String(format: "$%.2f", response.price))
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color("AccentYellow"))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Listing ID")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(response.listingId)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // View on eBay
                    Button {
                        if let url = URL(string: response.listingURL) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 15))
                            Text("View on eBay")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(Color("AccentYellow"))
                    }
                }
                .padding(20)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
                .opacity(contentOpacity)
                .offset(y: contentOffset)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onScanAnother) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                            Text("Scan Another Item")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color("AccentYellow"), in: RoundedRectangle(cornerRadius: 14))
                    }

                    Text("You'll be notified when it sells")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
                .opacity(contentOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                circleScale = 1.0
                circleOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                contentOpacity = 1.0
                contentOffset = 0
            }
        }
    }
}
