import XCTest
@testable import GirlPower

@MainActor
final class PaywallViewModelTests: XCTestCase {
    func testPriceAndTitleReflectProduct() {
        let product = PaywallProduct(
            id: "pro",
            displayName: "Girl Power Coaching",
            displayPrice: "$19.99",
            periodDescription: "month",
            features: []
        )
        let service = EntitlementServiceStub(initialState: .ready(product: product))
        let viewModel = PaywallViewModel(entitlementService: service)
        XCTAssertEqual(viewModel.titleText, "Girl Power Coaching")
        XCTAssertEqual(viewModel.priceText, "$19.99 / month")
        XCTAssertFalse(viewModel.isSubscribeDisabled)
    }

    func testProcessingStateDisablesButtons() {
        let product = PaywallProduct(
            id: "pro",
            displayName: "Girl Power Coaching",
            displayPrice: "$19.99",
            periodDescription: "month",
            features: []
        )
        let service = EntitlementServiceStub(initialState: .purchasing(product: product))
        let viewModel = PaywallViewModel(entitlementService: service)
        XCTAssertTrue(viewModel.isSubscribeDisabled)
        XCTAssertTrue(viewModel.isRestoreDisabled)
    }

    func testErrorMessageSurfaced() {
        let service = EntitlementServiceStub(initialState: .error(message: "No subscription", product: nil))
        let viewModel = PaywallViewModel(entitlementService: service)
        XCTAssertEqual(viewModel.errorMessage, "No subscription")
    }
}
