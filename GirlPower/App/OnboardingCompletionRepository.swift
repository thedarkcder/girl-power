import Foundation

protocol OnboardingCompletionRepository {
    var hasCompletedOnboarding: Bool { get }
    func markCompleted()
}

final class UserDefaultsOnboardingCompletionRepository: OnboardingCompletionRepository {
    private let defaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "onboarding.completed") {
        self.defaults = userDefaults
        self.key = key
    }

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: key)
    }

    func markCompleted() {
        defaults.set(true, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
