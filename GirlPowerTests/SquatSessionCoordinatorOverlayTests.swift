import CoreGraphics
import XCTest
@testable import GirlPower

final class SquatSessionCoordinatorOverlayTests: XCTestCase {
    @MainActor
    func testOverlayClearsDuringLowConfidencePhase() {
        let coordinator = SquatSessionCoordinator()
        let overlaySpy = OverlaySpy()
        coordinator.overlayOutput = overlaySpy

        let expectation = expectation(description: "overlay paused for low confidence")
        overlaySpy.onUpdate = { expectation.fulfill() }

        let pipeline = PoseDetectionPipeline()
        coordinator.poseDetectionPipeline(pipeline, didDetect: PoseFrame(timestamp: 0, landmarks: [:]))

        wait(for: [expectation], timeout: 1.0)
        XCTAssertNil(overlaySpy.lastFrame)
        XCTAssertEqual(overlaySpy.lastPhase, .coachingPausedLowConfidence)
    }

    @MainActor
    func testOverlayResumesWithFreshFrameAfterConfidenceRecovers() {
        let coordinator = SquatSessionCoordinator()
        let overlaySpy = OverlaySpy()
        coordinator.overlayOutput = overlaySpy
        let pipeline = PoseDetectionPipeline()

        let pauseExpectation = expectation(description: "overlay paused for low confidence")
        overlaySpy.onUpdate = { pauseExpectation.fulfill() }
        coordinator.poseDetectionPipeline(pipeline, didDetect: PoseFrame(timestamp: 0, landmarks: [:]))
        wait(for: [pauseExpectation], timeout: 1.0)

        let resumeExpectation = expectation(description: "overlay resumes after recovery")
        overlaySpy.onUpdate = { resumeExpectation.fulfill() }
        let validFrame = makeValidPoseFrame(timestamp: 1.0)
        coordinator.poseDetectionPipeline(pipeline, didDetect: validFrame)
        wait(for: [resumeExpectation], timeout: 1.0)

        XCTAssertEqual(overlaySpy.lastFrame, validFrame)
        XCTAssertNotEqual(overlaySpy.lastPhase, .coachingPausedLowConfidence)
    }
}

@MainActor
private final class OverlaySpy: SquatSessionCoordinatorOverlayOutput {
    var lastFrame: PoseFrame?
    var lastPhase: PosePhase?
    var onUpdate: (() -> Void)?

    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didUpdateOverlay frame: PoseFrame?, phase: PosePhase) {
        lastFrame = frame
        lastPhase = phase
        onUpdate?()
    }
}

private func makeValidPoseFrame(timestamp: TimeInterval) -> PoseFrame {
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
