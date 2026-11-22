import SwiftUI
import StoreKit

/// Purchase options and restore actions.
struct PaywallView: View {
    @ObservedObject var purchases: PurchaseManager
    let onDismiss: () -> Void

    @State private var selectedProductID: String = CaraokeProducts.yearly
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(hex: 0x0A0A0C).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top close bar
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close paywall")
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header Badge & Title
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [Color(hex: 0xFFB800), Color(hex: 0xFF8A00)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.black)
                            }
                            .shadow(color: Color(hex: 0xFFB800).opacity(0.35), radius: 12, y: 4)

                            Text("Unlock Caraoke Premium")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)

                            Text("Sing along with real-time synced lyrics everywhere.")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .padding(.top, 4)

                        // Feature checkmarks
                        VStack(alignment: .leading, spacing: 10) {
                            featureRow(icon: "car.fill", title: "Synced Lyrics on CarPlay Dashboard")
                            featureRow(icon: "lock.fill", title: "Lock Screen Live Activity")
                            featureRow(icon: "platter.2.filled.iphone", title: "Dynamic Island & StandBy Mode")
                            featureRow(icon: "square.grid.2x2.fill", title: "Home Screen Desktop Widgets")
                        }
                        .padding(.horizontal, 24)

                        if purchases.isEntitled {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(AppTheme.ok)
                                Text("Caraoke Plus is active on this account.")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.ok.opacity(0.14)))
                            .padding(.horizontal, 20)
                        }

                        // Plan cards
                        VStack(spacing: 12) {
                            ForEach(purchases.planOffers, id: \.productID) { offer in
                                planCard(offer: offer, isSelected: selectedProductID == offer.productID)
                            }
                        }
                        .padding(.horizontal, 20)

                        if purchases.loadFailed {
                            VStack(spacing: 8) {
                                Text("Could not reach App Store. Please check connection.")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.warn)
                                Button("Retry") {
                                    Task { await purchases.loadProducts() }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(hex: 0xFFB800))
                            }
                        }
                        Text("Subscriptions renew automatically. Cancel in Settings at least 24 hours before renewal.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        if let message = purchases.purchaseMessage {
                            Text(message)
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        // CTA Button
                        Button {
                            handlePurchase()
                        } label: {
                            HStack {
                                if purchases.purchaseInFlight {
                                    ProgressView().tint(.black)
                                } else {
                                    Text(ctaButtonText)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: 0xFFD600), Color(hex: 0xFFA000)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color(hex: 0xFFB800).opacity(0.3), radius: 10, y: 3)
                        }
                        .disabled(purchases.purchaseInFlight || !purchases.products.contains(where: { $0.id == selectedProductID }))
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                        // Bottom Actions
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) { legalActions }
                            VStack(spacing: 12) { legalActions }
                        }
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .onAppear {
            Analytics.signal("paywall_viewed")
            if purchases.products.isEmpty {
                Task { await purchases.loadProducts() }
            }
        }
    }

    @ViewBuilder
    private var legalActions: some View {
        Button("Restore Purchases") {
            Task { await purchases.restore() }
        }
        .disabled(purchases.purchaseInFlight)
        Link("Terms of Use", destination: URL(string: "https://caraokeapp.com/terms")!)
        Link("Privacy Policy", destination: URL(string: "https://caraokeapp.com/privacy")!)
    }

    private var ctaButtonText: String {
        if selectedProductID == CaraokeProducts.monthly {
            return "Subscribe Monthly"
        } else if selectedProductID == CaraokeProducts.lifetime {
            return "Get Lifetime Access"
        } else {
            return "Subscribe Yearly"
        }
    }

    private func handlePurchase() {
        guard let product = purchases.products.first(where: { $0.id == selectedProductID }) else {
            return
        }
        Task {
            let success = await purchases.purchase(product)
            if success {
                Analytics.signal("purchase_completed", parameters: ["product": selectedProductID])
                onDismiss()
            }
        }
    }

    private func featureRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: 0x34C759))
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
        }
    }

    private func planSubtitle(for offer: PlanOffer) -> String {
        if offer.productID == CaraokeProducts.lifetime {
            return "One-time purchase"
        }
        let base = offer.productID == CaraokeProducts.monthly ? "Renews monthly" : "Renews yearly"
        if let intro = purchases.introOfferDescription(for: offer.productID) {
            return "\(intro) · \(base)"
        }
        return base
    }

    private func planCard(offer: PlanOffer, isSelected: Bool) -> some View {
        Button {
            selectedProductID = offer.productID
        } label: {
            HStack(spacing: 14) {
                // Radio indicator
                Circle()
                    .strokeBorder(isSelected ? Color(hex: 0xFFB800) : Color.white.opacity(0.2), lineWidth: 2)
                    .background(Circle().fill(isSelected ? Color(hex: 0xFFB800) : Color.clear))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle().fill(Color.black).frame(width: 8, height: 8)
                            .opacity(isSelected ? 1 : 0)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(offer.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        if offer.productID == CaraokeProducts.yearly {
                            Text("SAVE 50%")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(hex: 0xFFB800)))
                        } else if offer.productID == CaraokeProducts.lifetime {
                            Text("FOUNDING")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.16)))
                        }
                    }
                    Text(planSubtitle(for: offer))
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer(minLength: 8)
                Text(purchases.priceText(for: offer))
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color(hex: 0x1E1E24) : Color(hex: 0x141416))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color(hex: 0xFFB800) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(purchases.purchaseInFlight)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
