import Foundation

enum DemoQuotaDependenciesFactory {
    static func makeCoordinator() -> DemoQuotaCoordinating {
        let configuration = DemoQuotaConfiguration.load()
        switch configuration.mode {
        case .mock:
            return makeMockCoordinator()
        case .supabase:
            if let supabase = configuration.supabase {
                return makeSupabaseCoordinator(config: supabase)
            }
            return makeMockCoordinator()
        }
    }

    private static func makeSupabaseCoordinator(config: DemoQuotaConfiguration.SupabaseEndpoints) -> DemoQuotaCoordinating {
        let persistence = UserDefaultsDemoAttemptRepository()
        let urlSession = URLSession(configuration: .default)
        let sessionLogger = SupabaseSessionLogger(endpoint: config.sessionLoggerURL, anonKey: config.anonKey, urlSession: urlSession)
        let evaluationService = EvaluateSessionService(endpoint: config.evaluateSessionURL, anonKey: config.anonKey, timeoutInterval: 3, urlSession: urlSession)
        let keychain = KeychainDeviceIdentityStorage()
        let identityProvider = DeviceIdentityProvider(keychain: keychain)
        return DemoQuotaCoordinator(
            persistence: persistence,
            sessionLogger: sessionLogger,
            evaluationService: evaluationService,
            identityProvider: identityProvider,
            snapshotSync: nil
        )
    }

    private static func makeMockCoordinator() -> DemoQuotaCoordinating {
        let persistence = UserDefaultsDemoAttemptRepository(prefix: "demo.quota.mock")
        let sessionLogger = ConsoleDemoSessionLogger()
        let evaluationService = MockDemoEvaluationService()
        let keychain = KeychainDeviceIdentityStorage(service: "com.route25.girlpower.deviceid.mock")
        let identityProvider = DeviceIdentityProvider(keychain: keychain)
        return DemoQuotaCoordinator(
            persistence: persistence,
            sessionLogger: sessionLogger,
            evaluationService: evaluationService,
            identityProvider: identityProvider,
            snapshotSync: nil
        )
    }
}
