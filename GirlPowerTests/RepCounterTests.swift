import XCTest
@testable import GirlPower

final class RepCounterTests: XCTestCase {
    func testCountsValidRepAfterDescentAndAscent() {
        var counter = RepCounter(configuration: .init(
            descentThreshold: 0.1,
            releaseThreshold: 0.03,
            minDwellTime: 0.15,
            minConfidence: 0.4,
            smoothingAlpha: 0.4,
            repCompletionHold: 0.1,
            invalidMotionGrace: 0.4,
            sampleResetInterval: 2.0
        ))

        let frames = [
            frame(time: 0.0, hip: 0.35),
            frame(time: 0.10, hip: 0.55),
            frame(time: 0.32, hip: 0.58),
            frame(time: 0.52, hip: 0.60),
            frame(time: 0.70, hip: 0.48),
            frame(time: 0.90, hip: 0.40)
        ]

        var result: RepCounter.Result?
        frames.forEach { frame in
            result = counter.process(frame: frame)
        }

        guard let finalResult = result else {
            return XCTFail("Missing result")
        }

        XCTAssertEqual(finalResult.repetitionCount, 1)
        if case let .repCompleted(repetitionCount, _) = finalResult.phase {
            XCTAssertEqual(repetitionCount, 1)
        } else {
            XCTFail("Expected rep completed phase")
        }
        XCTAssertEqual(finalResult.cue, .positive)
    }

    func testLowConfidencePausesCounting() {
        var counter = RepCounter()
        let frame = frame(time: 1.0, hip: 0.5, confidence: 0.2)
        let result = counter.process(frame: frame)
        XCTAssertEqual(result.phase, .coachingPausedLowConfidence)
        XCTAssertEqual(result.cue, .correction(.lowConfidence))
        XCTAssertEqual(result.repetitionCount, 0)
    }

    func testInsufficientDepthSendsCorrection() {
        var counter = RepCounter(configuration: .init(
            descentThreshold: 0.2,
            releaseThreshold: 0.05,
            minDwellTime: 0.2,
            minConfidence: 0.4,
            smoothingAlpha: 0.5,
            repCompletionHold: 0.1,
            invalidMotionGrace: 0.2,
            sampleResetInterval: 2.0
        ))

        _ = counter.process(frame: frame(time: 0.0, hip: 0.50))
        let result = counter.process(frame: frame(time: 0.25, hip: 0.44))
        XCTAssertEqual(result.phase, .idleWithinSet)
        XCTAssertEqual(result.cue, .correction(.insufficientDepth))
        XCTAssertEqual(result.repetitionCount, 0)
    }

    // MARK: - Helpers

    private func frame(
        time: TimeInterval,
        hip: CGFloat,
        knee: CGFloat = 0.4,
        ankle: CGFloat = 0.85,
        confidence: CGFloat = 0.9
    ) -> PoseFrame {
        let leftHip = PosePoint(position: CGPoint(x: 0.45, y: hip), confidence: confidence)
        let rightHip = PosePoint(position: CGPoint(x: 0.55, y: hip), confidence: confidence)
        let leftKnee = PosePoint(position: CGPoint(x: 0.45, y: knee), confidence: confidence)
        let rightKnee = PosePoint(position: CGPoint(x: 0.55, y: knee), confidence: confidence)
        let leftAnkle = PosePoint(position: CGPoint(x: 0.45, y: ankle), confidence: confidence)
        let rightAnkle = PosePoint(position: CGPoint(x: 0.55, y: ankle), confidence: confidence)

        return PoseFrame(
            timestamp: time,
            landmarks: [
                .leftHip: leftHip,
                .rightHip: rightHip,
                .leftKnee: leftKnee,
                .rightKnee: rightKnee,
                .leftAnkle: leftAnkle,
                .rightAnkle: rightAnkle
            ]
        )
    }
}
