import Foundation

struct PaywallProduct: Equatable {
    let id: String
    let displayName: String
    let displayPrice: String
    let periodDescription: String
    let features: [String]

    var pricePerPeriodDescription: String {
        "\(displayPrice) / \(periodDescription)"
    }
}

struct SubscriptionInfo: Equatable {
    let product: PaywallProduct
    let transactionID: UInt64
    let expirationDate: Date?
}

enum EntitlementState: Equatable {
    case loading
    case ready(product: PaywallProduct)
    case purchasing(product: PaywallProduct)
    case restoring(product: PaywallProduct)
    case subscribed(info: SubscriptionInfo)
    case error(message: String, product: PaywallProduct?)

    var paywallProduct: PaywallProduct? {
        switch self {
        case .ready(let product), .purchasing(let product), .restoring(let product):
            return product
        case .subscribed(let info):
            return info.product
        case .error(_, let product):
            return product
        case .loading:
            return nil
        }
    }

    var isSubscribed: Bool {
        if case .subscribed = self {
            return true
        }
        return false
    }
}
