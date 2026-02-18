import Foundation

protocol DemoEvaluationServicing {
    func evaluate(deviceID: UUID, attemptIndex: Int, context: [String: Any]) async throws -> EvaluationResult
}

struct EvaluationResult: Equatable {
    let allowAnotherDemo: Bool
    let message: String?
    let timestamp: Date
}

enum DemoEvaluationError: Error {
    case networkFailure
    case timeout
    case invalidResponse
}

final class EvaluateSessionService: DemoEvaluationServicing {
    private let urlSession: URLSession
    private let endpoint: URL
    private let anonKey: String
    private let timeoutInterval: TimeInterval

    init(endpoint: URL, anonKey: String, timeoutInterval: TimeInterval = 3, urlSession: URLSession = .shared) {
        self.endpoint = endpoint
        self.anonKey = anonKey
        self.timeoutInterval = timeoutInterval
        self.urlSession = urlSession
    }

    func evaluate(deviceID: UUID, attemptIndex: Int, context: [String: Any]) async throws -> EvaluationResult {
        var request = URLRequest(url: endpoint, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "device_id": deviceID.uuidString,
            "attempt_index": attemptIndex,
            "context": context
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                throw DemoEvaluationError.invalidResponse
            }
            let result = try JSONDecoder().decode(EvaluateResponse.self, from: data)
            return EvaluationResult(
                allowAnotherDemo: result.allowAnotherDemo,
                message: result.message,
                timestamp: Date()
            )
        } catch let error as URLError {
            if error.code == .timedOut {
                throw DemoEvaluationError.timeout
            }
            throw DemoEvaluationError.networkFailure
        }
    }

    private struct EvaluateResponse: Decodable {
        let allowAnotherDemo: Bool
        let message: String?
    }
}
