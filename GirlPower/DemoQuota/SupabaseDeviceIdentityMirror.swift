import Foundation

final class SupabaseDeviceIdentityMirror: DeviceIdentityMirroring {
    private struct MirrorPayload: Codable {
        let stableLookupKey: String
        let deviceID: String

        enum CodingKeys: String, CodingKey {
            case stableLookupKey = "stable_lookup_key"
            case deviceID = "device_id"
        }
    }

    private struct FetchResponse: Codable {
        let deviceID: String

        enum CodingKeys: String, CodingKey {
            case deviceID = "device_id"
        }
    }

    private let fetchEndpoint: URL
    private let mirrorEndpoint: URL
    private let anonKey: String
    private let urlSession: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fetchEndpoint: URL, mirrorEndpoint: URL, anonKey: String, urlSession: URLSession = .shared) {
        self.fetchEndpoint = fetchEndpoint
        self.mirrorEndpoint = mirrorEndpoint
        self.anonKey = anonKey
        self.urlSession = urlSession
    }

    func fetchDeviceID(stableLookupKey: String) async throws -> UUID? {
        guard var components = URLComponents(url: fetchEndpoint, resolvingAgainstBaseURL: false) else {
            throw DeviceIdentityError.networkUnavailable
        }
        components.queryItems = [URLQueryItem(name: "stable_lookup_key", value: stableLookupKey)]
        guard let url = components.url else {
            throw DeviceIdentityError.networkUnavailable
        }

        var request = baseRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeviceIdentityError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200:
            let payload = try decoder.decode(FetchResponse.self, from: data)
            return UUID(uuidString: payload.deviceID)
        case 204, 404:
            return nil
        default:
            throw DeviceIdentityError.networkUnavailable
        }
    }

    func mirror(deviceID: UUID, stableLookupKey: String) async throws {
        var request = baseRequest(url: mirrorEndpoint)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(MirrorPayload(stableLookupKey: stableLookupKey, deviceID: deviceID.uuidString))

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw DeviceIdentityError.networkUnavailable
        }
    }

    private func baseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 4
        return request
    }
}
