import XCTest
@testable import GirlPower

final class EntitlementStateMachineTests: XCTestCase {
    private let product = PaywallProduct(
        id: "pro",
        displayName: "Girl Power Coaching",
        displayPrice: "$19.99",
        periodDescription: "month",
        features: []
    )

    private func makeInfo() -> SubscriptionInfo {
        SubscriptionInfo(product: product, transactionID: 1, expirationDate: nil)
    }

    func testLoadingToReadyWhenProductsLoaded() {
        let machine = EntitlementStateMachine()
        let next = machine.transition(from: .loading, event: .productsLoaded(product))
        XCTAssertEqual(next, .ready(product: product))
    }

    func testPurchaseSuccessTransitionsToSubscribed() {
        let machine = EntitlementStateMachine()
        let purchasing = EntitlementState.purchasing(product: product)
        let next = machine.transition(from: purchasing, event: .entitlementVerified(makeInfo()))
        XCTAssertEqual(next, .subscribed(info: makeInfo()))
    }

    func testPurchaseFailureShowsErrorWithProduct() {
        let machine = EntitlementStateMachine()
        let purchasing = EntitlementState.purchasing(product: product)
        let next = machine.transition(from: purchasing, event: .purchaseFailed(message: "failed"))
        XCTAssertEqual(next, .error(message: "failed", product: product))
    }

    func testRevocationReturnsToReady() {
        let machine = EntitlementStateMachine()
        let subscribed = EntitlementState.subscribed(info: makeInfo())
        let next = machine.transition(from: subscribed, event: .revoked)
        XCTAssertEqual(next, .ready(product: product))
    }
}
