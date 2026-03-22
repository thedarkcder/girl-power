import Foundation
import OSLog

protocol OnboardingCompletionRepository {
    var hasCompletedOnboarding: Bool { get }
    func markCompleted()
    func syncWithProfile(using session: AuthSession) async -> Bool
}

final class UserDefaultsOnboardingCompletionRepository: OnboardingCompletionRepository {
    private let defaults: UserDefaults
    private let key: String
    private let profileService: any ProfileServicing
    private let logger = Logger(subsystem: "com.route25.GirlPower", category: "Onboarding")

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "onboarding.completed",
        profileService: any ProfileServicing = DisabledProfileService()
    ) {
        self.defaults = userDefaults
        self.key = key
        self.profileService = profileService
    }

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: key)
    }

    func markCompleted() {
        defaults.set(true, forKey: key)
    }

    func syncWithProfile(using session: AuthSession) async -> Bool {
        let localCompleted = hasCompletedOnboarding

        do {
            let profile: Profile
            if let fetched = try await profileService.fetchProfile(using: session) {
                profile = fetched
            } else {
                profile = try await profileService.upsertProfile(using: session)
            }
            if try await sync(profile: profile, localCompleted: localCompleted, using: session) {
                return true
            }
        } catch {
            logger.warning("Profile onboarding sync failed: \(error.localizedDescription, privacy: .public)")
        }

        return hasCompletedOnboarding
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    private func sync(
        profile: Profile,
        localCompleted: Bool,
        using session: AuthSession
    ) async throws -> Bool {
        if profile.onboardingCompleted {
            if localCompleted == false {
                defaults.set(true, forKey: key)
            }
            return true
        }

        guard localCompleted else {
            return false
        }

        _ = try await profileService.updateOnboardingCompleted(true, using: session)
        return true
    }
}
