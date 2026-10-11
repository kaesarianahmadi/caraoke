import Foundation

/// StoreKit / RevenueCat product identifiers and entitlement configuration.
enum CaraokeProducts {
    static let entitlementID = "caraoke_payment_plan"

    static let monthly = "monthly"
    static let yearly = "yearly"
    static let lifetime = "lifetime"
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
    static var plans: [PlanOffer] {
        plans(metadata: [:])
    }

    static func plans(metadata: [String: String]) -> [PlanOffer] {
        [
            PlanOffer(
                productID: CaraokeProducts.yearly,
                title: metadata["yearly_title"] ?? "Yearly",
                subtitle: metadata["yearly_subtitle"] ?? "3 days free, then $9.99/year ($0.83/mo)",
                fallbackPriceText: "$9.99 / yr",
                originalPriceText: nil,
                trialBadge: metadata["yearly_badge"] ?? "3-DAY FREE TRIAL",
                isRecommended: true
            ),
            PlanOffer(
                productID: CaraokeProducts.monthly,
                title: metadata["monthly_title"] ?? "Monthly",
                subtitle: metadata["monthly_subtitle"] ?? "3 days free, then $1.99/month",
                fallbackPriceText: "$1.99 / mo",
                originalPriceText: nil,
                trialBadge: metadata["monthly_badge"] ?? "3-DAY FREE TRIAL",
                isRecommended: false
            ),
            PlanOffer(
                productID: CaraokeProducts.lifetime,
                title: metadata["lifetime_title"] ?? "Lifetime",
                subtitle: metadata["lifetime_subtitle"] ?? "One-time purchase, yours forever",
                fallbackPriceText: "$14.99 once (was $20 launch special)",
                originalPriceText: metadata["lifetime_anchor"] ?? "$27.00",
                trialBadge: metadata["lifetime_badge"] ?? "45% OFF",
                isRecommended: false
            ),
        ]
    }
}
