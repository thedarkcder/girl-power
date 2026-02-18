import CoreGraphics
import XCTest
@testable import GirlPower

@MainActor
final class SquatSessionCoordinatorSummaryTests: XCTestCase {
    func testPresentSummaryTransitionsToSummaryState() async {
        let coordinator = SquatSessionCoordinator()
        let stateSpy = CoordinatorStateSpy()
        coordinator.output = stateSpy

        let runningExpectation = expectation(description: "entered running state")
        let summaryExpectation = expectation(description: "presented summary")
        let context = SummaryContext(summary: makeSummary(), ctaState: .awaitingDecision)

        stateSpy.onStateChange = { state in
            if case .running = state {
                runningExpectation.fulfill()
            }
            if case .summary(let receivedContext) = state {
                XCTAssertEqual(receivedContext, context)
                summaryExpectation.fulfill()
            }
        }

        let pipeline = PoseDetectionPipeline()
        coordinator.poseDetectionPipeline(pipeline, didDetect: makePoseFrame(timestamp: 0.5))

        await fulfillment(of: [runningExpectation], timeout: 1.0)

        coordinator.presentSummary(context)

        await fulfillment(of: [summaryExpectation], timeout: 1.0)
    }

    private func makeSummary() -> SessionSummary {
        SessionSummary(
            attemptIndex: 1,
            totalReps: 4,
            tempoInsight: .steady,
            averageTempoSeconds: 1.2,
            coachingNotes: [],
            duration: 12,
            generatedAt: Date()
        )
    }
}

@MainActor
private final class CoordinatorStateSpy: SquatSessionCoordinatorOutput {
    var onStateChange: ((SquatSessionStateMachine.State) -> Void)?

    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didTransitionTo state: SquatSessionStateMachine.State) {
        onStateChange?(state)
    }

    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didUpdate result: RepCounter.Result) {}

    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didEncounter error: SquatSessionError) {}
}

private func makePoseFrame(timestamp: TimeInterval) -> PoseFrame {
    let confidence: CGFloat = 0.9
    let landmarks: [PoseJoint: PosePoint] = [
        .leftHip: PosePoint(position: CGPoint(x: 0.4, y: 0.6), confidence: confidence),
        .rightHip: PosePoint(position: CGPoint(x: 0.6, y: 0.6), confidence: confidence),
        .leftKnee: PosePoint(position: CGPoint(x: 0.4, y: 0.5), confidence: confidence),
        .rightKnee: PosePoint(position: CGPoint(x: 0.6, y: 0.5), confidence: confidence),
        .leftAnkle: PosePoint(position: CGPoint(x: 0.4, y: 0.8), confidence: confidence),
        .rightAnkle: PosePoint(position: CGPoint(x: 0.6, y: 0.8), confidence: confidence),
        .leftShoulder: PosePoint(position: CGPoint(x: 0.4, y: 0.3), confidence: confidence),
        .rightShoulder: PosePoint(position: CGPoint(x: 0.6, y: 0.3), confidence: confidence)
    ]
    return PoseFrame(timestamp: timestamp, landmarks: landmarks)
}
