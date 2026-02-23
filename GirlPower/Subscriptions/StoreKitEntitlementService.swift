import Foundation
import OSLog
import StoreKit

@MainActor
protocol EntitlementServicing: ObservableObject {
    var state: EntitlementState { get }
    var isPro: Bool { get }

    func load() async
    func purchase() async
    func restore() async
    func observeStates() -> AsyncStream<EntitlementState>
}

@MainActor
final class StoreKitEntitlementService: ObservableObject, EntitlementServicing {
    @Published private(set) var state: EntitlementState
    @Published private(set) var isPro: Bool

    private let productIDs: [String]
    private var currentProduct: Product?
    private let stateMachine = EntitlementStateMachine()
    private let snapshotStore: EntitlementSnapshotPersisting
    private var continuations: [UUID: AsyncStream<EntitlementState>.Continuation] = [:]
    private var updatesTask: Task<Void, Never>?
    private var cachedIsPro: Bool
    private let logger = Logger(subsystem: "com.girlpower.app", category: "Entitlements")

    init(
        productIDs: [String],
        snapshotStore: EntitlementSnapshotPersisting = UserDefaultsEntitlementSnapshotStore()
    ) {
        self.productIDs = productIDs
        self.snapshotStore = snapshotStore
        self.state = .loading
        let snapshot = snapshotStore.load()
        self.cachedIsPro = snapshot?.isPro ?? false
        self.isPro = snapshot?.isPro ?? false
    }

    deinit {
        updatesTask?.cancel()
    }

    func observeStates() -> AsyncStream<EntitlementState> {
        AsyncStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let id = UUID()
                continuation.onTermination = { [weak self] _ in
                    Task { @MainActor in
                        self?.continuations[id] = nil
                    }
                }
                self.continuations[id] = continuation
                continuation.yield(self.state)
            }
        }
    }

    func load() async {
        await loadProductsIfNeeded()
        await refreshCurrentEntitlements()
        startTransactionListenerIfNeeded()
    }

    func purchase() async {
        guard let product = currentProduct else {
            apply(.error(message: "Product unavailable."))
            return
        }
        apply(.purchaseStarted)
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                try await handleVerifiedPurchase(verification)
            case .userCancelled:
                apply(.purchaseCancelled)
            case .pending:
                apply(.purchaseFailed(message: "Purchase pending. Check with Apple Support."))
            @unknown default:
                apply(.purchaseFailed(message: "Unknown purchase result."))
            }
        } catch {
            apply(.purchaseFailed(message: error.localizedDescription))
        }
    }

    func restore() async {
        if currentProduct == nil {
            await loadProductsIfNeeded()
        }
        apply(.restoreStarted)
        var restored = false
        do {
            for await entitlement in Transaction.currentEntitlements {
                let matched = try await handleTransactionResult(entitlement, finishTransaction: false)
                restored = restored || matched
            }
            if !restored {
                clearSnapshot()
                apply(.restoreFailed(message: "No active subscription found."))
            }
        } catch {
            apply(.restoreFailed(message: error.localizedDescription))
        }
    }

    // MARK: - Private helpers

    private func loadProductsIfNeeded() async {
        guard currentProduct == nil else { return }
        do {
            let products = try await Product.products(for: productIDs)
            guard let product = products.first else {
                apply(.error(message: "No products configured."))
                return
            }
            currentProduct = product
            let paywallProduct = makePaywallProduct(from: product)
            apply(.productsLoaded(paywallProduct))
        } catch {
            logger.error("Failed to load products: \(error.localizedDescription)")
            apply(.error(message: "Unable to reach the App Store. Try again."))
        }
    }

    private func refreshCurrentEntitlements() async {
        var found = false
        do {
            for await result in Transaction.currentEntitlements {
                let matched = try await handleTransactionResult(result, finishTransaction: false)
                found = found || matched
            }
            if !found {
                clearSnapshot()
                refreshIsPro()
            }
        } catch {
            logger.error("Failed to refresh current entitlements: \(error.localizedDescription)")
        }
    }

    private func startTransactionListenerIfNeeded() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                do {
                    _ = try await self?.handleTransactionResult(result, finishTransaction: true)
                } catch {
                    await MainActor.run {
                        self?.logger.error("Transaction listener failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    @discardableResult
    private func handleTransactionResult(
        _ result: VerificationResult<Transaction>,
        finishTransaction: Bool
    ) async throws -> Bool {
        switch result {
        case .verified(let transaction):
            guard productIDs.contains(transaction.productID) else { return false }
            let info = SubscriptionInfo(
                product: await currentPaywallProduct() ?? makePaywallProduct(from: transaction),
                transactionID: transaction.id,
                expirationDate: transaction.expirationDate
            )
            apply(.entitlementVerified(info))
            persistSnapshot(for: info)
            if finishTransaction {
                await transaction.finish()
            }
            if transaction.revocationDate != nil {
                apply(.revoked)
                clearSnapshot()
                refreshIsPro()
            }
            return true
        case .unverified(_, let error):
            logger.error("Unverified transaction: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func handleVerifiedPurchase(_ result: VerificationResult<Transaction>) async throws {
        do {
            try await handleTransactionResult(result, finishTransaction: true)
        } catch {
            apply(.purchaseFailed(message: error.localizedDescription))
            throw error
        }
    }

    private func makePaywallProduct(from product: Product) -> PaywallProduct {
        PaywallProduct(
            id: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            periodDescription: product.subscription?.subscriptionPeriod.localizedDescription ?? "month",
            features: defaultFeatures()
        )
    }

    private func makePaywallProduct(from transaction: Transaction) -> PaywallProduct {
        if let product = currentProduct {
            return makePaywallProduct(from: product)
        }
        return PaywallProduct(
            id: transaction.productID,
            displayName: "Girl Power Coaching",
            displayPrice: state.paywallProduct?.displayPrice ?? "$19.99",
            periodDescription: state.paywallProduct?.periodDescription ?? "month",
            features: defaultFeatures()
        )
    }

    private func currentPaywallProduct() async -> PaywallProduct? {
        if let product = state.paywallProduct {
            return product
        }
        if let product = currentProduct {
            return makePaywallProduct(from: product)
        }
        return nil
    }

    private func persistSnapshot(for info: SubscriptionInfo) {
        let snapshot = EntitlementSnapshot(isPro: true, productID: info.product.id, lastUpdated: Date())
        snapshotStore.save(snapshot)
        cachedIsPro = true
        refreshIsPro()
    }

    private func clearSnapshot() {
        snapshotStore.clear()
        cachedIsPro = false
    }

    private func apply(_ event: EntitlementStateMachine.Event) {
        let next = stateMachine.transition(from: state, event: event)
        updateState(next)
    }

    private func updateState(_ next: EntitlementState) {
        guard state != next else {
            refreshIsPro()
            continuations.values.forEach { $0.yield(next) }
            return
        }
        state = next
        refreshIsPro()
        continuations.values.forEach { $0.yield(next) }
    }

    private func refreshIsPro() {
        let effective = cachedIsPro || state.isSubscribed
        if isPro != effective {
            isPro = effective
        }
    }

    private func defaultFeatures() -> [String] {
        [
            "Unlimited AI coaching sessions",
            "Personalized squat insights",
            "Real-time voice cues"
        ]
    }
}

private extension Product.SubscriptionPeriod {
    var localizedDescription: String {
        switch unit {
        case .day:
            return value == 7 ? "week" : "day"
        case .week:
            return value == 1 ? "week" : "weeks"
        case .month:
            return value == 1 ? "month" : "months"
        case .year:
            return value == 1 ? "year" : "years"
        @unknown default:
            return "month"
        }
    }
}
