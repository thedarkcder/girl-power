import CoreGraphics
import Foundation

enum PoseJoint: String, CaseIterable {
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
    case leftShoulder
    case rightShoulder
}

struct PosePoint: Equatable {
    let position: CGPoint
    let confidence: CGFloat
}

struct PoseFrame: Equatable {
    let timestamp: TimeInterval
    private(set) var landmarks: [PoseJoint: PosePoint]

    init(timestamp: TimeInterval, landmarks: [PoseJoint: PosePoint]) {
        self.timestamp = timestamp
        self.landmarks = landmarks
    }

    var averageLowerBodyConfidence: CGFloat {
        let targets: [PoseJoint] = [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        let confidences = targets.compactMap { landmarks[$0]?.confidence }
        guard !confidences.isEmpty else { return 0 }
        let sum = confidences.reduce(0, +)
        return sum / CGFloat(confidences.count)
    }

    func point(_ joint: PoseJoint) -> PosePoint? {
        landmarks[joint]
    }

    func midpoint(_ first: PoseJoint, _ second: PoseJoint) -> CGPoint? {
        guard let firstPoint = landmarks[first]?.position,
              let secondPoint = landmarks[second]?.position
        else { return nil }
        return CGPoint(
            x: (firstPoint.x + secondPoint.x) / 2,
            y: (firstPoint.y + secondPoint.y) / 2
        )
    }

    var hipMidpoint: CGPoint? {
        midpoint(.leftHip, .rightHip)
    }

    var kneeMidpoint: CGPoint? {
        midpoint(.leftKnee, .rightKnee)
    }

    var ankleMidpoint: CGPoint? {
        midpoint(.leftAnkle, .rightAnkle)
    }
}

enum PosePhase: Equatable {
    case idleWithinSet
    case descending(progress: CGFloat)
    case ascending(progress: CGFloat)
    case repCompleted(repetitionCount: Int, timestamp: TimeInterval)
    case coachingPausedLowConfidence
}

enum CoachingCue: Equatable {
    case positive
    case correction(CorrectionReason)

    enum CorrectionReason: String, Equatable {
        case insufficientDepth
        case instability
        case lowConfidence
    }
}

enum SquatSessionInterruption: Equatable {
    case audioSession
    case captureRuntime
    case applicationBackgrounded
    case other(String)
}

enum SquatSessionError: Error, Equatable {
    case cameraUnavailable
    case permissionsDenied
    case configurationFailed(String)
    case captureFailed(String)
}
