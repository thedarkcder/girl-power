import Foundation

final class ConsoleDemoSessionLogger: DemoSessionLogging {
    func logAttempt(deviceID: UUID, attemptIndex: Int, stage: DemoSessionStage, metadata: [String : Any]) async throws {}
}

final class MockDemoEvaluationService: DemoEvaluationServicing {
    func evaluate(deviceID: UUID, attemptIndex: Int, context: [String : Any]) async throws -> EvaluationResult {
        EvaluationResult(
            allowAnotherDemo: attemptIndex == 1,
            message: nil,
            lockReason: nil,
            attemptsUsed: attemptIndex,
            timestamp: Date()
        )
    }
}
