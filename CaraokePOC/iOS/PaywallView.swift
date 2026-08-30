import SwiftUI

/// The paywall per PRD D6: shown only after the first successful lyric
/// moment, never at install. Apple-like — plain, three plans, yearly
/// recommended, lifetime secondary.
struct PaywallView: View {
    @ObservedObject var purchases: PurchaseManager
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("Make every ride a sing-along")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Keep live lyrics ready on CarPlay, whenever the chorus comes on.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)

            VStack(spacing: 10) {
                ForEach(PaywallContent.plans, id: \.productID) { offer in
                    planRow(offer)
                }
            }
            .padding(.horizontal)

            if purchases.loadFailed {
                Text("Couldn't reach the App Store. Try again later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Restore purchases") {
                Task { await purchases.restore() }
            }
            .font(.footnote)

            Text("Subscriptions auto-renew until cancelled in Settings. Manage or cancel anytime in your Apple ID settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .padding(.bottom)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func planRow(_ offer: PlanOffer) -> some View {
        let isLoading = !purchases.products.isEmpty
        Button {
            guard let product = purchases.products.first(where: { $0.id == offer.productID }) else { return }
            Task { await purchases.purchase(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(offer.title)
                            .font(.headline)
                        if offer.isRecommended {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.18), in: Capsule())
                        }
                    }
                    Text(offer.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if purchases.purchaseInFlight {
                    ProgressView()
                } else {
                    Text(purchases.priceText(for: offer))
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .opacity(isLoading || !purchases.products.isEmpty ? 1 : 0.8)
        }
        .buttonStyle(.plain)
        .disabled(purchases.purchaseInFlight)
    }
}
