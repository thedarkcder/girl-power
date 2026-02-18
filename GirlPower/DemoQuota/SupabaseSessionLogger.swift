import Foundation

enum DemoSessionStage: Equatable {
    case start
    case completion
}

protocol DemoSessionLogging {
    func logAttempt(
        deviceID: UUID,
        attemptIndex: Int,
        stage: DemoSessionStage,
        metadata: [String: Any]
    ) async throws
}

enum DemoSessionLoggingError: Error {
    case invalidResponse
    case networkFailure
}

final class SupabaseSessionLogger: DemoSessionLogging {
    private let urlSession: URLSession
    private let endpoint: URL
    private let anonKey: String

    init(endpoint: URL, anonKey: String, urlSession: URLSession = .shared) {
        self.endpoint = endpoint
        self.anonKey = anonKey
        self.urlSession = urlSession
    }

    func logAttempt(deviceID: UUID, attemptIndex: Int, stage: DemoSessionStage, metadata: [String: Any]) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "device_id": deviceID.uuidString,
            "attempt_index": attemptIndex,
            "stage": stage == .start ? "start" : "completion",
            "metadata": metadata
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw DemoSessionLoggingError.invalidResponse
        }
        if data.isEmpty == false {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
        }
    }
}
