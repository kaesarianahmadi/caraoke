import Foundation

/// StoreKit product identifiers — one entitlement ("Caraoke Plus"), three
/// plans per the locked decisions: $1.99/mo · $11.99/yr · $20 lifetime.
enum CaraokeProducts {
    static let monthly = "caraoke.plus.monthly"
    static let yearly = "caraoke.plus.yearly"
    static let lifetime = "caraoke.plus.lifetime"
    static let all: Set<String> = [monthly, yearly, lifetime]

    /// One entitlement, any plan grants it. StoreKit 2's
    /// `Transaction.currentEntitlements` already resolves renewals, refunds,
    /// and family sharing — ownership of any listed product is the whole rule.
    static func isEntitled(productIDs: Set<String>) -> Bool {
        !productIDs.isDisjoint(with: all)
    }
}

/// Paywall presentation model — pure data, testable without StoreKit.
/// Runtime price text comes from `Product.displayPrice`; these literals are
/// the fallback and the store-listing source of truth.
struct PlanOffer: Equatable, Sendable {
    let productID: String
    let title: String
    let subtitle: String
    let fallbackPriceText: String
    let isRecommended: Bool
}

enum PaywallContent {
    /// Display order: yearly first (recommended), monthly, lifetime last and
    /// secondary per the brainstorm's monetization flow.
    static let plans: [PlanOffer] = [
        PlanOffer(productID: CaraokeProducts.yearly,
                  title: "Yearly",
                  subtitle: "Best value — just $1.00/month",
                  fallbackPriceText: "$11.99 / year",
                  isRecommended: true),
        PlanOffer(productID: CaraokeProducts.monthly,
                  title: "Monthly",
                  subtitle: "Try it for a trip",
                  fallbackPriceText: "$1.99 / month",
                  isRecommended: false),
        PlanOffer(productID: CaraokeProducts.lifetime,
                  title: "Founding Lifetime",
                  subtitle: "One payment. Keep Caraoke forever.",
                  fallbackPriceText: "$20 once — limited launch offer",
                  isRecommended: false),
    ]
}
