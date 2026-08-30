import Foundation
import StoreKit

/// StoreKit 2 manager for the single "Caraoke Plus" entitlement.
/// Deliberately no RevenueCat and no backend at this scale: StoreKit 2
/// transactions are the source of truth, `Transaction.updates` covers
/// out-of-process renewals/refunds, and `AppStore.sync()` covers restore.
@MainActor
final class PurchaseManager: ObservableObject {

    @Published private(set) var products: [Product] = []
    @Published private(set) var isEntitled = false
    @Published private(set) var loadFailed = false
    @Published private(set) var purchaseInFlight = false

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            // Out-of-process events: renewals, refunds, family-sharing grants.
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
        do {
            products = try await Product.products(for: CaraokeProducts.all.sorted())
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
        }
    }

    /// Returns true when the purchase completed and granted the entitlement.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
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
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var owned = Set<String>()
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               CaraokeProducts.all.contains(transaction.productID) {
                owned.insert(transaction.productID)
            }
        }
        isEntitled = CaraokeProducts.isEntitled(productIDs: owned)
    }

    /// Localized price for a product ID, falling back to the paywall's
    /// literal text while products are loading (or offline).
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
