import Foundation
import OSLog

enum ProPlatform: String, Codable, Equatable {
    case apple
    case external
}

struct Profile: Codable, Equatable {
    let id: String
    let email: String?
    let createdAt: Date
    let updatedAt: Date
    let isPro: Bool
    let proPlatform: ProPlatform?
    let onboardingCompleted: Bool
    let lastLoginAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isPro = "is_pro"
        case proPlatform = "pro_platform"
        case onboardingCompleted = "onboarding_completed"
        case lastLoginAt = "last_login_at"
    }
}

enum ProfileServiceError: Error, Equatable {
    case invalidResponse
    case networkUnavailable
}

protocol ProfileServicing {
    func fetchProfile(using session: AuthSession) async throws -> Profile?
    func upsertProfile(using session: AuthSession) async throws -> Profile
    func updateOnboardingCompleted(_ completed: Bool, using session: AuthSession) async throws -> Profile
    func mirrorEntitlement(isPro: Bool, platform: ProPlatform?, using session: AuthSession) async throws -> Profile
}

struct DisabledProfileService: ProfileServicing {
    func fetchProfile(using session: AuthSession) async throws -> Profile? {
        nil
    }

    func upsertProfile(using session: AuthSession) async throws -> Profile {
        makeFallbackProfile(using: session)
    }

    func updateOnboardingCompleted(_ completed: Bool, using session: AuthSession) async throws -> Profile {
        let profile = makeFallbackProfile(using: session)
        return Profile(
            id: profile.id,
            email: profile.email,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt,
            isPro: profile.isPro,
            proPlatform: profile.proPlatform,
            onboardingCompleted: completed,
            lastLoginAt: profile.lastLoginAt
        )
    }

    func mirrorEntitlement(isPro: Bool, platform: ProPlatform?, using session: AuthSession) async throws -> Profile {
        let profile = makeFallbackProfile(using: session)
        return Profile(
            id: profile.id,
            email: profile.email,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt,
            isPro: isPro,
            proPlatform: platform,
            onboardingCompleted: profile.onboardingCompleted,
            lastLoginAt: profile.lastLoginAt
        )
    }

    private func makeFallbackProfile(using session: AuthSession) -> Profile {
        let now = Date()
        return Profile(
            id: session.user.id,
            email: session.user.email,
            createdAt: now,
            updatedAt: now,
            isPro: false,
            proPlatform: nil,
            onboardingCompleted: false,
            lastLoginAt: now
        )
    }
}

final class SupabaseProfileService: ProfileServicing {
    private let configuration: SupabaseProjectConfiguration
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger = Logger(subsystem: "com.route25.GirlPower", category: "Profiles")

    init(configuration: SupabaseProjectConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.decoder = Self.makeDecoder()
        self.encoder = Self.makeEncoder()
    }

    func fetchProfile(using session: AuthSession) async throws -> Profile? {
        let request = try makeRequest(
            session: session,
            method: "GET",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
                URLQueryItem(name: "select", value: Self.selectClause)
            ]
        )
        let data = try await perform(request)
        let profiles = try decoder.decode([Profile].self, from: data)
        return profiles.first
    }

    func upsertProfile(using session: AuthSession) async throws -> Profile {
        let request = try makeRequest(
            session: session,
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "id"),
                URLQueryItem(name: "select", value: Self.selectClause)
            ],
            prefer: "resolution=merge-duplicates,return=representation",
            body: try encoder.encode([
                ProfileUpsertPayload(
                    id: session.user.id,
                    email: session.user.email,
                    lastLoginAt: Date()
                )
            ])
        )
        return try await decodeSingleProfile(from: request)
    }

    func updateOnboardingCompleted(_ completed: Bool, using session: AuthSession) async throws -> Profile {
        let request = try makeRequest(
            session: session,
            method: "PATCH",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
                URLQueryItem(name: "select", value: Self.selectClause)
            ],
            prefer: "return=representation",
            body: try encoder.encode(ProfileOnboardingPatch(onboardingCompleted: completed))
        )
        return try await decodeSingleProfile(from: request)
    }

    func mirrorEntitlement(isPro: Bool, platform: ProPlatform?, using session: AuthSession) async throws -> Profile {
        let request = try makeRequest(
            session: session,
            method: "PATCH",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
                URLQueryItem(name: "select", value: Self.selectClause)
            ],
            prefer: "return=representation",
            body: try encoder.encode(ProfileEntitlementPatch(isPro: isPro, proPlatform: platform))
        )
        return try await decodeSingleProfile(from: request)
    }

    private func decodeSingleProfile(from request: URLRequest) async throws -> Profile {
        let data = try await perform(request)
        let profiles = try decoder.decode([Profile].self, from: data)
        guard let profile = profiles.first else {
            throw ProfileServiceError.invalidResponse
        }
        return profile
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ProfileServiceError.invalidResponse
            }
            return data
        } catch let error as ProfileServiceError {
            throw error
        } catch {
            logger.warning("Supabase profile request failed: \(error.localizedDescription, privacy: .public)")
            throw ProfileServiceError.networkUnavailable
        }
    }

    private func makeRequest(
        session: AuthSession,
        method: String,
        queryItems: [URLQueryItem] = [],
        prefer: String? = nil,
        body: Data? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(url: configuration.profilesURL, resolvingAgainstBaseURL: false) else {
            throw ProfileServiceError.invalidResponse
        }
        if queryItems.isEmpty == false {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw ProfileServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.httpBody = body
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("public", forHTTPHeaderField: "Accept-Profile")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" {
            request.setValue("public", forHTTPHeaderField: "Content-Profile")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        return request
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let date = fractionalDateFormatter.date(from: rawValue) ?? internetDateFormatter.date(from: rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date format: \(rawValue)")
        }
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalDateFormatter.string(from: date))
        }
        return encoder
    }

    private static let selectClause = "id,email,created_at,updated_at,is_pro,pro_platform,onboarding_completed,last_login_at"

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct ProfileUpsertPayload: Encodable {
    let id: String
    let email: String?
    let lastLoginAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case lastLoginAt = "last_login_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if let email {
            try container.encode(email, forKey: .email)
        }
        try container.encode(lastLoginAt, forKey: .lastLoginAt)
    }
}

private struct ProfileOnboardingPatch: Encodable {
    let onboardingCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case onboardingCompleted = "onboarding_completed"
    }
}

private struct ProfileEntitlementPatch: Encodable {
    let isPro: Bool
    let proPlatform: ProPlatform?

    enum CodingKeys: String, CodingKey {
        case isPro = "is_pro"
        case proPlatform = "pro_platform"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isPro, forKey: .isPro)
        if let proPlatform {
            try container.encode(proPlatform, forKey: .proPlatform)
        } else {
            try container.encodeNil(forKey: .proPlatform)
        }
    }
}

extension SupabaseProjectConfiguration {
    var profilesURL: URL {
        projectURL.appendingPathComponent("rest/v1/profiles")
    }
}
