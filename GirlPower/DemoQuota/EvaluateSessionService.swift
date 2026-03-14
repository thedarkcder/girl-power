import Foundation

protocol DemoEvaluationServicing {
    func evaluate(deviceID: UUID, attemptIndex: Int, context: [String: Any]) async throws -> EvaluationResult
}

struct EvaluationResult: Equatable {
    let allowAnotherDemo: Bool
    let message: String?
    let lockReason: String?
    let attemptsUsed: Int
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

        let prompt = """
        Evaluate whether the caller is eligible for exactly one additional free Girl Power coaching demo after attempt \(attemptIndex). Use the structured context for audit only and fail closed if quota or validation checks fail.
        """
        let payload: [String: Any] = [
            "device_id": deviceID.uuidString,
            "attempt_index": attemptIndex,
            "payload_version": "v1",
            "input": [
                "prompt": prompt,
                "context": context
            ],
            "metadata": context
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DemoEvaluationError.invalidResponse
            }
            if [409, 429].contains(httpResponse.statusCode) {
                return try decodeResult(from: data)
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                throw DemoEvaluationError.invalidResponse
            }
            return try decodeResult(from: data)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw DemoEvaluationError.timeout
            }
            throw DemoEvaluationError.networkFailure
        }
    }

    private func decodeResult(from data: Data) throws -> EvaluationResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.timestampFormatter.date(from: value) ?? Self.fallbackTimestampFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 timestamp")
        }
        let result = try decoder.decode(EvaluateResponse.self, from: data)
        return EvaluationResult(
            allowAnotherDemo: result.allowAnotherDemo,
            message: result.message,
            lockReason: result.lockReason,
            attemptsUsed: result.attemptsUsed,
            timestamp: result.evaluatedAt ?? Date()
        )
    }

    private struct EvaluateResponse: Decodable {
        let allowAnotherDemo: Bool
        let message: String?
        let lockReason: String?
        let attemptsUsed: Int
        let evaluatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case allowAnotherDemo = "allow_another_demo"
            case message
            case lockReason = "lock_reason"
            case attemptsUsed = "attempts_used"
            case evaluatedAt = "evaluated_at"
        }
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
