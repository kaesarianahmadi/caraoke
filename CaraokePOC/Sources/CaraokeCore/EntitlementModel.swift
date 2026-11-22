import Foundation

/// StoreKit / RevenueCat product identifiers and entitlement configuration.
enum CaraokeProducts {
    static let entitlementID = "caraoke_payment_plan"

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
}

enum PaywallContent {
    static let plans = [
        PlanOffer(productID: CaraokeProducts.yearly, title: "Yearly"),
        PlanOffer(productID: CaraokeProducts.monthly, title: "Monthly"),
        PlanOffer(productID: CaraokeProducts.lifetime, title: "Lifetime"),
    ]
}
