import SwiftUI
import PhotosUI

struct CreateListingView: View {
    @State private var draft: DraftListing
    let priceAnalysis: PriceAnalysis
    let onBack: () -> Void
    let onSuccess: (PostedListingResponse) -> Void

    @State private var isPosting = false
    @State private var postError: String?
    @State private var showError = false
    @State private var photoPickerItem: PhotosPickerItem?

    private var topSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 0
    }

    @EnvironmentObject private var appState: AppState

    init(draft: DraftListing, priceAnalysis: PriceAnalysis, onBack: @escaping () -> Void, onSuccess: @escaping (PostedListingResponse) -> Void) {
        _draft = State(initialValue: draft)
        self.priceAnalysis = priceAnalysis
        self.onBack = onBack
        self.onSuccess = onSuccess
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(UIColor.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom nav bar
                navBar

                // Form
                ScrollView {
                    VStack(spacing: 24) {
                        photoSection
                        Divider()
                        titleSection
                        Divider()
                        priceSection
                        Divider()
                        conditionSection
                        Divider()
                        descriptionSection
                        Divider()
                        listingTypeSection
                        Divider()
                        shippingSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
            }

            // Submit bar
            submitBar
        }
        .alert("Listing Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(postError ?? "Something went wrong.")
        }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 16))
                }
                .foregroundStyle(.primary)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Create Listing")
                    .font(.system(size: 16, weight: .semibold))
                Text("eBay · Quick List")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Invisible spacer to center title
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.top, topSafeArea + 14)
        .padding(.bottom, 14)
        .background(Color(UIColor.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Sections

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Photo")

            HStack(spacing: 12) {
                // Main photo
                if let img = draft.capturedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color("AccentYellow").opacity(0.6), lineWidth: 1.5)
                        )
                }

                // Add more photos button
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                        Text("Add Photo")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 88, height: 88)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                    )
                }
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Title")
            TextField("Item title", text: $draft.title, axis: .vertical)
                .font(.system(size: 15))
                .padding(12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            Text("\(draft.title.count)/80 characters")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Price")

            HStack(alignment: .center, spacing: 4) {
                Text("$")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color("AccentYellow"))

                TextField("0.00", value: $draft.price, format: .number)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .keyboardType(.decimalPad)
                    .frame(width: 140)
            }
            .padding(.vertical, 4)

            // Price suggestion chips
            VStack(alignment: .leading, spacing: 6) {
                Text("Based on sold history")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    PriceChip(label: "Low",       value: priceAnalysis.low,           selectedPrice: draft.price, onTap: { draft.price = priceAnalysis.low })
                    PriceChip(label: "Suggested", value: priceAnalysis.suggestedPrice, selectedPrice: draft.price, onTap: { draft.price = priceAnalysis.suggestedPrice })
                    PriceChip(label: "Avg",       value: priceAnalysis.average,        selectedPrice: draft.price, onTap: { draft.price = priceAnalysis.average })
                    PriceChip(label: "High",      value: priceAnalysis.high,           selectedPrice: draft.price, onTap: { draft.price = priceAnalysis.high })
                }
            }
        }
    }

    private var conditionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Condition")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ItemCondition.allCases, id: \.self) { condition in
                    ConditionOption(
                        condition: condition,
                        isSelected: draft.condition == condition,
                        onTap: { draft.condition = condition }
                    )
                }
            }
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Description")
            TextEditor(text: $draft.description)
                .font(.system(size: 14))
                .frame(height: 100)
                .padding(10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var listingTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Listing Type")

            VStack(spacing: 8) {
                ForEach(ListingType.allCases, id: \.self) { type in
                    ListingTypeRow(
                        type: type,
                        isSelected: draft.listingType == type,
                        onTap: { draft.listingType = type }
                    )
                }
            }
        }
    }

    private var shippingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Shipping")

            VStack(spacing: 8) {
                ForEach(ShippingOption.allCases, id: \.self) { option in
                    ShippingRow(
                        option: option,
                        isSelected: draft.shippingOption == option,
                        onTap: { draft.shippingOption = option }
                    )
                }
            }
        }
    }

    // MARK: - Submit Bar

    private var submitBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Listing for")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", draft.price))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color("AccentYellow"))
                }

                Spacer()

                Button(action: submitListing) {
                    Group {
                        if isPosting {
                            ProgressView().tint(.black)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 16))
                                Text("List on eBay")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .frame(height: 50)
                    .background(Color("AccentYellow"), in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isPosting || draft.price <= 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 83)   // 34pt home indicator + 49pt custom tab bar
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Submit

    private func submitListing() {
        isPosting = true
        Task {
            do {
                let response = try await EbayListingService.shared.publishListing(draft)
                await MainActor.run {
                    isPosting = false
                    // Save to local listings
                    appState.myListings.append(
                        EbayListing(
                            id: response.listingId,
                            title: draft.title,
                            price: draft.price,
                            currency: "USD",
                            condition: draft.condition,
                            soldDate: nil,
                            imageURL: nil,
                            listingURL: response.listingURL,
                            sellerFeedback: nil,
                            shippingCost: draft.shippingOption.estimatedCost,
                            isAuction: draft.listingType != .fixedPrice,
                            bidsCount: nil
                        )
                    )
                    onSuccess(response)
                }
            } catch {
                await MainActor.run {
                    isPosting = false
                    postError = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Supporting Components

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.8)
            .textCase(.uppercase)
    }
}

struct PriceChip: View {
    let label: String
    let value: Double
    let selectedPrice: Double
    let onTap: () -> Void

    private var isSelected: Bool { abs(selectedPrice - value) < 0.01 }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : .secondary)
                    .kerning(0.5)
                    .textCase(.uppercase)
                Text(String(format: "$%.0f", value))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? .black : .primary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Color("AccentYellow") : Color(.systemGray6),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
    }
}

struct ConditionOption: View {
    let condition: ItemCondition
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(condition.shortLabel)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .black : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    isSelected ? Color("AccentYellow") : Color(.systemGray6),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color("AccentYellow") : .clear, lineWidth: 1)
                )
        }
    }
}

struct ListingTypeRow: View {
    let type: ListingType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color("AccentYellow") : .secondary)
                    .font(.system(size: 18))
                Text(type.rawValue)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                isSelected ? Color("AccentYellow").opacity(0.08) : Color(.systemGray6),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
    }
}

struct ShippingRow: View {
    let option: ShippingOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color("AccentYellow") : .secondary)
                    .font(.system(size: 18))
                Text(option.rawValue)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
                Text(option.displayCost)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                isSelected ? Color("AccentYellow").opacity(0.08) : Color(.systemGray6),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
    }
}
