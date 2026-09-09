import Foundation

/// StoreKit product identifiers — one entitlement ("Caraoke Plus"), three
/// plans per locked decisions: $1.99/mo (3-day trial) · $9.99/yr · $14.99 lifetime (was $20 / $27).
enum CaraokeProducts {
    static let monthly = "caraoke.plus.monthly"
    static let yearly = "caraoke.plus.yearly"
    static let lifetime = "caraoke.plus.lifetime"
    static let all: Set<String> = [monthly, yearly, lifetime]

    static func isEntitled(productIDs: Set<String>) -> Bool {
        !productIDs.isDisjoint(with: all)
    }
}

/// Paywall presentation model — pure data, testable without StoreKit.
struct PlanOffer: Equatable, Sendable {
    let productID: String
    let title: String
    let subtitle: String
    let fallbackPriceText: String
    let originalPriceText: String?
    let trialBadge: String?
    let isRecommended: Bool
}

enum PaywallContent {
    /// Plans: Yearly first (3-day trial, recommended), Monthly (3-day trial), Lifetime launch special.
    static let plans: [PlanOffer] = [
        PlanOffer(
            productID: CaraokeProducts.yearly,
            title: "Yearly",
            subtitle: "3 days free, then $9.99/year ($0.83/mo)",
            fallbackPriceText: "$9.99 / yr",
            originalPriceText: nil,
            trialBadge: "3-DAY FREE TRIAL",
            isRecommended: true
        ),
        PlanOffer(
            productID: CaraokeProducts.monthly,
            title: "Monthly",
            subtitle: "3 days free, then $1.99/month",
            fallbackPriceText: "$1.99 / mo",
            originalPriceText: nil,
            trialBadge: "3-DAY FREE TRIAL",
            isRecommended: false
        ),
        PlanOffer(
            productID: CaraokeProducts.lifetime,
            title: "Lifetime",
            subtitle: "One-time purchase, yours forever",
            fallbackPriceText: "$14.99 once (was $20 launch special)",
            originalPriceText: "$27.00",
            trialBadge: "45% OFF",
            isRecommended: false
        ),
    ]
}
