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
    @Published private(set) var purchaseMessage: String?

    var planOffers: [PlanOffer] { PaywallContent.plans }

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
        // StoreKit products provide the storefront-localized price.

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
        guard !purchaseInFlight else { return false }
        purchaseInFlight = true
        purchaseMessage = nil
        defer { purchaseInFlight = false }

        #if canImport(RevenueCat)
        if Purchases.isConfigured {
            do {
                guard let rcProduct = try await Purchases.shared.products([product.id]).first else {
                    purchaseMessage = "This product is unavailable. Please try again later."
                    return false
                }
                let result = try await Purchases.shared.purchase(product: rcProduct)
                if result.userCancelled { return false }
                if result.customerInfo.entitlements[CaraokeProducts.entitlementID]?.isActive == true {
                    isEntitled = true
                    return true
                }
                purchaseMessage = "Purchase not confirmed. If approval is pending, access will update after approval."
            } catch {
                let nsError = error as NSError
                if nsError.domain == RevenueCat.ErrorCode.errorDomain {
                    if nsError.code == RevenueCat.ErrorCode.purchaseCancelledError.rawValue { return false }
                    if nsError.code == RevenueCat.ErrorCode.paymentPendingError.rawValue {
                        purchaseMessage = "Purchase pending approval. Access will update after approval."
                        return false
                    }
                }
                purchaseMessage = "Purchase failed: \(error.localizedDescription)"
            }
            return false
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
                    purchaseMessage = "Purchase could not be verified. Please contact Apple Support."
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                purchaseMessage = "Purchase pending approval. Access will update after approval."
                return false
            @unknown default:
                purchaseMessage = "Purchase could not be completed. Please try again."
                return false
            }
        } catch {
            purchaseMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    func restore() async {
        guard !purchaseInFlight else { return }
        purchaseInFlight = true
        purchaseMessage = nil
        defer { purchaseInFlight = false }
        do {
            #if canImport(RevenueCat)
            if Purchases.isConfigured {
                _ = try await Purchases.shared.restorePurchases()
            }
            #endif
            try await AppStore.sync()
            await refreshEntitlement()
            purchaseMessage = isEntitled ? "Purchases restored." : "No purchases found to restore."
        } catch {
            purchaseMessage = "Restore failed: \(error.localizedDescription)"
        }
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
        guard let product = products.first(where: { $0.id == offer.productID }) else {
            return "Unavailable"
        }
        return product.displayPrice
    }
}
