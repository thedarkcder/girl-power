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
        let deviceIdentityMirror = SupabaseDeviceIdentityMirror(fetchEndpoint: config.identityFetchURL, mirrorEndpoint: config.identityMirrorURL, anonKey: config.anonKey, urlSession: urlSession)
        let keychain = KeychainDeviceIdentityStorage()
        let identityProvider = DeviceIdentityProvider(keychain: keychain, serverMirror: deviceIdentityMirror)
        let snapshotSync = SupabaseDemoQuotaSnapshotSync(fetchEndpoint: config.snapshotFetchURL, mirrorEndpoint: config.snapshotMirrorURL, anonKey: config.anonKey, urlSession: urlSession)
        return DemoQuotaCoordinator(
            persistence: persistence,
            sessionLogger: sessionLogger,
            evaluationService: evaluationService,
            identityProvider: identityProvider,
            snapshotSync: snapshotSync
        )
    }

    private static func makeMockCoordinator() -> DemoQuotaCoordinating {
        let persistence = UserDefaultsDemoAttemptRepository(prefix: "demo.quota.mock")
        let sessionLogger = ConsoleDemoSessionLogger()
        let evaluationService = MockDemoEvaluationService()
        let identityMirror = NoopDeviceIdentityMirror()
        let keychain = KeychainDeviceIdentityStorage(service: "com.route25.girlpower.deviceid.mock")
        let identityProvider = DeviceIdentityProvider(keychain: keychain, serverMirror: identityMirror)
        return DemoQuotaCoordinator(
            persistence: persistence,
            sessionLogger: sessionLogger,
            evaluationService: evaluationService,
            identityProvider: identityProvider,
            snapshotSync: nil
        )
    }
}
