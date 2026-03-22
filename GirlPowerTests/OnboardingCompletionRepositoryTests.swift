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

    func testSyncWithProfileMarksLocalCompletedWhenServerProfileAlreadyCompleted() async {
        let suiteName = "test.syncRemoteOnboarding"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let profileService = OnboardingProfileServiceStub(
            fetchedProfile: Profile(
                id: "user-1",
                email: "member@example.com",
                createdAt: Date(),
                updatedAt: Date(),
                isPro: false,
                proPlatform: nil,
                onboardingCompleted: true,
                lastLoginAt: Date()
            )
        )
        let repository = UserDefaultsOnboardingCompletionRepository(
            userDefaults: defaults,
            key: "flag",
            profileService: profileService
        )

        let synced = await repository.syncWithProfile(using: .fixture)
        let updates = await profileService.updatedOnboardingStates()

        XCTAssertTrue(synced)
        XCTAssertTrue(repository.hasCompletedOnboarding)
        XCTAssertEqual(updates, [])
    }

    func testSyncWithProfileWritesAuthenticatedCompletionBackToServer() async {
        let suiteName = "test.pushLocalOnboarding"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let profileService = OnboardingProfileServiceStub(
            fetchedProfile: Profile(
                id: "user-1",
                email: "member@example.com",
                createdAt: Date(),
                updatedAt: Date(),
                isPro: false,
                proPlatform: nil,
                onboardingCompleted: false,
                lastLoginAt: Date()
            )
        )
        let repository = UserDefaultsOnboardingCompletionRepository(
            userDefaults: defaults,
            key: "flag",
            profileService: profileService
        )

        repository.markCompleted()
        let synced = await repository.syncWithProfile(using: .fixture)
        let updates = await profileService.updatedOnboardingStates()

        XCTAssertTrue(synced)
        XCTAssertTrue(repository.hasCompletedOnboarding)
        XCTAssertEqual(updates, [true])
    }
}

private actor OnboardingProfileServiceStub: ProfileServicing {
    let fetchedProfile: Profile?
    private var onboardingUpdates: [Bool] = []

    init(fetchedProfile: Profile?) {
        self.fetchedProfile = fetchedProfile
    }

    func fetchProfile(using session: AuthSession) async throws -> Profile? {
        fetchedProfile
    }

    func upsertProfile(using session: AuthSession) async throws -> Profile {
        fetchedProfile ?? Profile(
            id: session.user.id,
            email: session.user.email,
            createdAt: Date(),
            updatedAt: Date(),
            isPro: false,
            proPlatform: nil,
            onboardingCompleted: false,
            lastLoginAt: Date()
        )
    }

    func updateOnboardingCompleted(_ completed: Bool, using session: AuthSession) async throws -> Profile {
        onboardingUpdates.append(completed)
        return Profile(
            id: session.user.id,
            email: session.user.email,
            createdAt: Date(),
            updatedAt: Date(),
            isPro: false,
            proPlatform: nil,
            onboardingCompleted: completed,
            lastLoginAt: Date()
        )
    }

    func mirrorEntitlement(isPro: Bool, platform: ProPlatform?, using session: AuthSession) async throws -> Profile {
        try await upsertProfile(using: session)
    }

    func updatedOnboardingStates() -> [Bool] {
        onboardingUpdates
    }
}

private extension AuthSession {
    static var fixture: AuthSession {
        AuthSession(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
    }
}
