import Foundation

struct EntitlementStateMachine {
    enum Event: Equatable {
        case productsLoaded(PaywallProduct)
        case entitlementVerified(SubscriptionInfo)
        case purchaseStarted
        case purchaseFailed(message: String)
        case purchaseCancelled
        case restoreStarted
        case restoreFailed(message: String)
        case revoked
        case error(message: String)
        case retry
    }

    func transition(from state: EntitlementState, event: Event) -> EntitlementState {
        switch (state, event) {
        case (.loading, .productsLoaded(let product)):
            return .ready(product: product)

        case (.loading, .entitlementVerified(let info)):
            return .subscribed(info: info)

        case (.loading, .error(let message)):
            return .error(message: message, product: nil)

        case (.ready(let product), .productsLoaded(let newProduct)):
            return .ready(product: newProduct)

        case (.ready, .purchaseStarted):
            guard let product = state.paywallProduct else { return state }
            return .purchasing(product: product)

        case (.ready, .restoreStarted):
            guard let product = state.paywallProduct else { return state }
            return .restoring(product: product)

        case (.ready(let product), .error(let message)):
            return .error(message: message, product: product)

        case (.ready, .entitlementVerified(let info)):
            return .subscribed(info: info)

        case (.purchasing, .entitlementVerified(let info)):
            return .subscribed(info: info)

        case (.purchasing(let product), .purchaseFailed(let message)):
            return .error(message: message, product: product)

        case (.purchasing(let product), .purchaseCancelled):
            return .ready(product: product)

        case (.restoring, .entitlementVerified(let info)):
            return .subscribed(info: info)

        case (.restoring(let product), .restoreFailed(let message)):
            return .error(message: message, product: product)

        case (.subscribed(let info), .revoked):
            return .ready(product: info.product)

        case (.error(_, let product), .retry):
            if let product {
                return .ready(product: product)
            }
            return .loading

        case (.error, .productsLoaded(let product)):
            return .ready(product: product)

        case (.error, .entitlementVerified(let info)):
            return .subscribed(info: info)

        case (.error(let message, let product), .error):
            return .error(message: message, product: product)

        default:
            if case .error(_, let product) = state,
               case .error(let message) = event {
                return .error(message: message, product: product)
            }
            return state
        }
    }
}
