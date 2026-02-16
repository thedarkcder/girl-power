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

    func testResetClearsFlag() {
        let suiteName = "test.resetFlag"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let repository = UserDefaultsOnboardingCompletionRepository(userDefaults: defaults, key: "flag")

        repository.markCompleted()
        XCTAssertTrue(repository.hasCompletedOnboarding)

        repository.reset()
        XCTAssertFalse(repository.hasCompletedOnboarding)
    }
}
