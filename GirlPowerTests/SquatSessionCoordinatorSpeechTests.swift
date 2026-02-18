import XCTest
@testable import GirlPower

@MainActor
final class SquatSessionCoordinatorSpeechTests: XCTestCase {
    func testTrackingLossEnqueuesLowConfidenceCue() {
        let speechSpy = SpeechManagerSpy()
        let coordinator = SquatSessionCoordinator(
            cameraManager: CameraSessionManager(),
            posePipeline: PoseDetectionPipeline(),
            repCounter: RepCounter(),
            speechManager: speechSpy
        )

        let pipeline = PoseDetectionPipeline()
        coordinator.poseDetectionPipelineDidLoseTracking(pipeline)

        XCTAssertEqual(speechSpy.enqueuedCues, [.correction(.lowConfidence)])
    }
}

private final class SpeechManagerSpy: CoachingSpeechManaging {
    private(set) var enqueuedCues: [CoachingCue] = []

    func enqueue(cue: CoachingCue) {
        enqueuedCues.append(cue)
    }

    func stop() {}
}
