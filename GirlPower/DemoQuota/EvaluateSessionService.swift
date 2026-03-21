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
    private static let payloadVersion = "v1"
    private static let defaultPrompt = "Evaluate whether this device should unlock another free coaching demo."

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
            "payload_version": Self.payloadVersion,
            "input": [
                "prompt": Self.defaultPrompt,
                "context": context,
            ],
            "metadata": context,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DemoEvaluationError.invalidResponse
            }
            return try parseEvaluationResult(data: data, statusCode: httpResponse.statusCode)
        } catch let error as DemoEvaluationError {
            throw error
        } catch let error as URLError {
            if error.code == .timedOut {
                throw DemoEvaluationError.timeout
            }
            throw DemoEvaluationError.networkFailure
        } catch {
            throw DemoEvaluationError.invalidResponse
        }
    }

    private func parseEvaluationResult(data: Data, statusCode: Int) throws -> EvaluationResult {
        guard (200..<300).contains(statusCode) || statusCode == 409 || statusCode == 429 else {
            throw DemoEvaluationError.invalidResponse
        }

        let result = try JSONDecoder().decode(EvaluateResponse.self, from: data)
        let now = Date()

        switch result.decision.outcome {
        case .allow:
            return EvaluationResult(
                allowAnotherDemo: true,
                message: nil,
                lockReason: nil,
                attemptsUsed: 1,
                timestamp: now
            )
        case .deny:
            return EvaluationResult(
                allowAnotherDemo: false,
                message: result.decision.message,
                lockReason: result.decision.lockReason,
                attemptsUsed: 1,
                timestamp: now
            )
        case .timeout:
            throw DemoEvaluationError.timeout
        }
    }

    private struct EvaluateResponse: Decodable {
        let decision: Decision
    }

    private struct Decision: Decodable {
        let outcome: Outcome
        let message: String?
        let lockReason: String?

        enum CodingKeys: String, CodingKey {
            case outcome
            case message
            case lockReason = "lock_reason"
        }
    }

    private enum Outcome: String, Decodable {
        case allow
        case deny
        case timeout
    }
}
