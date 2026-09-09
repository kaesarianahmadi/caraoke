import SwiftUI
import StoreKit

/// Custom Paywall matching competitor design (IMG_5088):
/// - OLED dark card surface
/// - Feature highlights
/// - Monthly ($1.99 with 3-Day Free Trial)
/// - Yearly ($9.99 with Best Value badge)
/// - Lifetime ($14.99 with $27.00 strikethrough & 45% Off)
/// - One-tap primary CTA button + Restore Purchases
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
                            .foregroundColor(.white.opacity(0.4))
                    }
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

                        // Plan cards
                        VStack(spacing: 12) {
                            ForEach(PaywallContent.plans, id: \.productID) { offer in
                                planCard(offer: offer, isSelected: selectedProductID == offer.productID)
                            }
                        }
                        .padding(.horizontal, 20)

                        if purchases.loadFailed {
                            Text("Could not reach App Store. Please check connection.")
                                .font(.caption)
                                .foregroundColor(AppTheme.warn)
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
                            .frame(height: 52)
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
                        .disabled(purchases.purchaseInFlight)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                        // Bottom Actions
                        HStack(spacing: 16) {
                            Button("Restore Purchases") {
                                Task { await purchases.restore() }
                            }
                            Text("•").foregroundColor(.white.opacity(0.2))
                            Link("Terms of Use", destination: URL(string: "https://caraoke.live/docs")!)
                            Text("•").foregroundColor(.white.opacity(0.2))
                            Link("Privacy Policy", destination: URL(string: "https://caraoke.live/docs")!)
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.bottom, 20)
                    }
                }
            }
        }
    }

    private var ctaButtonText: String {
        if selectedProductID == CaraokeProducts.monthly {
            return "Start 3-Day Free Trial"
        } else if selectedProductID == CaraokeProducts.lifetime {
            return "Get Lifetime Access"
        } else {
            return "Subscribe Yearly"
        }
    }

    private func handlePurchase() {
        guard let product = purchases.products.first(where: { $0.id == selectedProductID }) else {
            // If offline/unloaded, fallback action
            return
        }
        Task {
            let success = await purchases.purchase(product)
            if success { onDismiss() }
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

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(offer.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)

                        if let badge = offer.trialBadge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(isSelected ? .black : Color(hex: 0xFFB800))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color(hex: 0xFFB800) : Color(hex: 0xFFB800).opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }

                    Text(offer.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let orig = offer.originalPriceText {
                        Text(orig)
                            .font(.system(size: 12))
                            .strikethrough(true, color: .white.opacity(0.5))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Text(offer.fallbackPriceText)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
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
    }
}
