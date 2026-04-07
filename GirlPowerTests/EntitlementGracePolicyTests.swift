import XCTest
@testable import GirlPower

final class EntitlementGracePolicyTests: XCTestCase {
    func testEffectiveIsProTrueWhenSubscribedEvenWithoutSnapshot() {
        let policy = EntitlementGracePolicy(
            isSubscribed: true,
            hasValidatedSnapshot: false,
            revalidationGraceDeadline: nil
        )

        XCTAssertTrue(policy.effectiveIsPro(now: Date()))
    }

    func testEffectiveIsProTrueWhenSnapshotExistsAndDeadlineInFuture() {
        let now = Date(timeIntervalSince1970: 100)
        let policy = EntitlementGracePolicy(
            isSubscribed: false,
            hasValidatedSnapshot: true,
            revalidationGraceDeadline: now.addingTimeInterval(5)
        )

        XCTAssertTrue(policy.effectiveIsPro(now: now))
    }

    func testEffectiveIsProFalseWhenGraceDeadlineExpires() {
        let now = Date(timeIntervalSince1970: 100)
        let policy = EntitlementGracePolicy(
            isSubscribed: false,
            hasValidatedSnapshot: true,
            revalidationGraceDeadline: now
        )

        XCTAssertFalse(policy.effectiveIsPro(now: now))
    }

    func testEffectiveIsProFalseWithoutValidatedSnapshot() {
        let policy = EntitlementGracePolicy(
            isSubscribed: false,
            hasValidatedSnapshot: false,
            revalidationGraceDeadline: Date().addingTimeInterval(10)
        )

        XCTAssertFalse(policy.effectiveIsPro(now: Date()))
    }

    func testGraceDeadlineReturnsNilWhenSnapshotMissing() {
        let deadline = EntitlementGracePolicy.graceDeadline(
            hasValidatedSnapshot: false,
            now: Date(timeIntervalSince1970: 1),
            gracePeriod: 10
        )

        XCTAssertNil(deadline)
    }

    func testGraceDeadlineOffsetsByConfiguredPeriod() {
        let now = Date(timeIntervalSince1970: 100)
        let deadline = EntitlementGracePolicy.graceDeadline(
            hasValidatedSnapshot: true,
            now: now,
            gracePeriod: 12
        )

        XCTAssertEqual(deadline, now.addingTimeInterval(12))
    }
}
