import XCTest
@testable import GirlPower

final class OnboardingCompletionRepositoryTests: XCTestCase {
    func testMarkCompletedPersistsFlag() {
        let defaults = UserDefaults(suiteName: "test.markCompleted")!
        defaults.removePersistentDomain(forName: "test.markCompleted")
        let repository = UserDefaultsOnboardingCompletionRepository(userDefaults: defaults, key: "flag")

        XCTAssertFalse(repository.hasCompletedOnboarding)
        repository.markCompleted()
        XCTAssertTrue(repository.hasCompletedOnboarding)
    }
}
