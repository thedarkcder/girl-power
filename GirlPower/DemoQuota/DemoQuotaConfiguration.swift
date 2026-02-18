import Foundation

struct DemoQuotaConfiguration {
    enum Mode: String {
        case mock
        case supabase
    }

    struct SupabaseEndpoints {
        let sessionLoggerURL: URL
        let evaluateSessionURL: URL
        let snapshotFetchURL: URL
        let snapshotMirrorURL: URL
        let identityFetchURL: URL
        let identityMirrorURL: URL
        let anonKey: String
    }

    let mode: Mode
    let supabase: SupabaseEndpoints?

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DemoQuotaConfiguration {
        let info = bundle.infoDictionary ?? [:]
        let modeString = environment["DEMO_QUOTA_MODE"] ?? info["DemoQuotaMode"] as? String ?? Mode.mock.rawValue
        let mode = Mode(rawValue: modeString.lowercased()) ?? .mock

        guard mode == .supabase,
              let supabaseConfig = SupabaseEndpoints(info: info, environment: environment)
        else {
            return DemoQuotaConfiguration(mode: .mock, supabase: nil)
        }

        return DemoQuotaConfiguration(mode: .supabase, supabase: supabaseConfig)
    }
}

private extension DemoQuotaConfiguration.SupabaseEndpoints {
    init?(info: [String: Any], environment: [String: String]) {
        guard let sessionLoggerURL = DemoQuotaConfiguration.url(key: "DemoQuotaSessionLoggerURL", env: "DEMO_QUOTA_SESSION_LOGGER_URL", info: info, environment: environment),
              let evaluateSessionURL = DemoQuotaConfiguration.url(key: "DemoQuotaEvaluateSessionURL", env: "DEMO_QUOTA_EVALUATE_SESSION_URL", info: info, environment: environment),
              let snapshotFetchURL = DemoQuotaConfiguration.url(key: "DemoQuotaSnapshotFetchURL", env: "DEMO_QUOTA_SNAPSHOT_FETCH_URL", info: info, environment: environment),
              let snapshotMirrorURL = DemoQuotaConfiguration.url(key: "DemoQuotaSnapshotMirrorURL", env: "DEMO_QUOTA_SNAPSHOT_MIRROR_URL", info: info, environment: environment),
              let identityFetchURL = DemoQuotaConfiguration.url(key: "DemoQuotaIdentityFetchURL", env: "DEMO_QUOTA_IDENTITY_FETCH_URL", info: info, environment: environment),
              let identityMirrorURL = DemoQuotaConfiguration.url(key: "DemoQuotaIdentityMirrorURL", env: "DEMO_QUOTA_IDENTITY_MIRROR_URL", info: info, environment: environment),
              let anonKey = DemoQuotaConfiguration.value(key: "DemoQuotaAnonKey", env: "DEMO_QUOTA_ANON_KEY", info: info, environment: environment),
              anonKey.isEmpty == false else {
            return nil
        }

        self.init(
            sessionLoggerURL: sessionLoggerURL,
            evaluateSessionURL: evaluateSessionURL,
            snapshotFetchURL: snapshotFetchURL,
            snapshotMirrorURL: snapshotMirrorURL,
            identityFetchURL: identityFetchURL,
            identityMirrorURL: identityMirrorURL,
            anonKey: anonKey
        )
    }
}

private extension DemoQuotaConfiguration {
    static func url(key: String, env: String, info: [String: Any], environment: [String: String]) -> URL? {
        guard let value = value(key: key, env: env, info: info, environment: environment),
              let url = URL(string: value)
        else { return nil }
        return url
    }

    static func value(key: String, env: String, info: [String: Any], environment: [String: String]) -> String? {
        if let envValue = environment[env], envValue.isEmpty == false {
            return envValue
        }
        if let infoValue = info[key] as? String, infoValue.isEmpty == false {
            return infoValue
        }
        return nil
    }
}
