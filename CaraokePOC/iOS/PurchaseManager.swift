import Foundation
import StoreKit
#if canImport(RevenueCat)
import RevenueCat
#endif

/// Purchase Manager supporting RevenueCat + StoreKit 2:
/// - Connects to RevenueCat backend if configured (or API key set in Secrets)
/// - Native StoreKit 2 transactions as source of truth
/// - Provides entitlement state, product loading, and purchase processing
@MainActor
final class PurchaseManager: ObservableObject {

    @Published private(set) var products: [Product] = []
    @Published private(set) var isEntitled = false
    @Published private(set) var loadFailed = false
    @Published private(set) var purchaseInFlight = false
    @Published private(set) var offeringMetadata: [String: String] = [:]

    var planOffers: [PlanOffer] {
        PaywallContent.plans(metadata: offeringMetadata)
    }

    func ctaText(for productID: String, defaultText: String) -> String {
        switch productID {
        case CaraokeProducts.monthly:
            return offeringMetadata["cta_monthly"] ?? defaultText
        case CaraokeProducts.yearly:
            return offeringMetadata["cta_yearly"] ?? defaultText
        case CaraokeProducts.lifetime:
            return offeringMetadata["cta_lifetime"] ?? defaultText
        default:
            return defaultText
        }
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        #if canImport(RevenueCat)
        if let key = SecretsLoader.revenueCatAPIKey {
            #if DEBUG
            Purchases.configure(withAPIKey: key)
            #else
            // RevenueCat throws fatalError in Release builds if a "test_" API key is used.
            // Only configure RevenueCat in Release builds when a production Apple key ("appl_") is present.
            if !key.hasPrefix("test_") {
                Purchases.configure(withAPIKey: key)
            }
            #endif
        }
        #endif

        updatesTask = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refreshEntitlement()
            }
        }
        Task {
            await refreshEntitlement()
            await loadProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        #if canImport(RevenueCat)
        if Purchases.isConfigured, let offerings = try? await Purchases.shared.offerings() {
            if let meta = offerings.current?.metadata {
                var strMeta: [String: String] = [:]
                for (k, v) in meta {
                    if let str = v as? String {
                        strMeta[k] = str
                    }
                }
                self.offeringMetadata = strMeta
            }
        }
        #endif

        do {
            products = try await Product.products(for: CaraokeProducts.all.sorted())
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
        }
    }

    /// Purchase execution via RevenueCat / StoreKit 2
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        #if canImport(RevenueCat)
        if Purchases.isConfigured,
           let rcProduct = try? await Purchases.shared.products([product.id]).first {
            do {
                let result = try await Purchases.shared.purchase(product: rcProduct)
                if result.customerInfo.entitlements[CaraokeProducts.entitlementID]?.isActive == true {
                    self.isEntitled = true
                    return true
                }
            } catch {
                // If RevenueCat purchase encounters an error, proceed to StoreKit 2 fallback
            }
        }
        #endif

        // Native StoreKit 2 path
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlement()
                    return true
                case .unverified:
                    return false
                }
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    func restore() async {
        #if canImport(RevenueCat)
        if Purchases.isConfigured {
            _ = try? await Purchases.shared.restorePurchases()
        }
        #endif
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        #if canImport(RevenueCat)
        if Purchases.isConfigured, let info = try? await Purchases.shared.customerInfo() {
            if info.entitlements[CaraokeProducts.entitlementID]?.isActive == true {
                isEntitled = true
                return
            }
        }
        #endif

        var owned = Set<String>()
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               CaraokeProducts.all.contains(transaction.productID) {
                owned.insert(transaction.productID)
            }
        }
        isEntitled = CaraokeProducts.isEntitled(productIDs: owned)
    }

    func priceText(for offer: PlanOffer) -> String {
        if let product = products.first(where: { $0.id == offer.productID }) {
            return "\(product.displayPrice) / \(unit(for: product.id))"
        }
        return offer.fallbackPriceText
    }

    private func unit(for productID: String) -> String {
        switch productID {
        case CaraokeProducts.yearly: return "year"
        case CaraokeProducts.monthly: return "month"
        default: return "once"
        }
    }
}
