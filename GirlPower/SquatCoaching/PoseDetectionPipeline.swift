import AVFoundation
import CoreVideo
import Vision

protocol PoseDetectionPipelineDelegate: AnyObject {
    func poseDetectionPipeline(_ pipeline: PoseDetectionPipeline, didDetect frame: PoseFrame)
    func poseDetectionPipelineDidLoseTracking(_ pipeline: PoseDetectionPipeline)
    func poseDetectionPipeline(_ pipeline: PoseDetectionPipeline, didFail error: Error)
}

final class PoseDetectionPipeline {
    weak var delegate: PoseDetectionPipelineDelegate?

    private let request = VNDetectHumanBodyPoseRequest()
    private let visionQueue = DispatchQueue(label: "com.girlpower.pose-detection", qos: .userInitiated)
    private var isProcessing = false
    private var isCancelled = false

    func process(sampleBuffer: CMSampleBuffer) {
        guard !isCancelled else { return }
        guard !isProcessing else { return }
        isProcessing = true
        let buffer = sampleBuffer
        visionQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isProcessing = false }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else {
                self.notifyLoss()
                return
            }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([self.request])
                guard let observation = self.request.results?.first else {
                    self.notifyLoss()
                    return
                }
                if let frame = self.makePoseFrame(from: observation, timestamp: timestamp) {
                    self.dispatch(frame: frame)
                } else {
                    self.notifyLoss()
                }
            } catch {
                self.delegate?.poseDetectionPipeline(self, didFail: error)
            }
        }
    }

    func cancel() {
        isCancelled = true
    }

    func resume() {
        isCancelled = false
    }

    private func dispatch(frame: PoseFrame) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.poseDetectionPipeline(self, didDetect: frame)
        }
    }

    private func notifyLoss() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.poseDetectionPipelineDidLoseTracking(self)
        }
    }

    private func makePoseFrame(from observation: VNHumanBodyPoseObservation, timestamp: TimeInterval) -> PoseFrame? {
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else { return nil }
        var mapped: [PoseJoint: PosePoint] = [:]
        for joint in PoseJoint.allCases {
            guard let point = recognizedPoints[joint.visionName], point.confidence > 0 else { continue }
            let normalized = CGPoint(x: CGFloat(point.location.x), y: 1 - CGFloat(point.location.y))
            mapped[joint] = PosePoint(position: normalized, confidence: CGFloat(point.confidence))
        }
        guard !mapped.isEmpty else { return nil }
        return PoseFrame(timestamp: timestamp, landmarks: mapped)
    }
}

private extension PoseJoint {
    var visionName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .leftHip:
            return .leftHip
        case .rightHip:
            return .rightHip
        case .leftKnee:
            return .leftKnee
        case .rightKnee:
            return .rightKnee
        case .leftAnkle:
            return .leftAnkle
        case .rightAnkle:
            return .rightAnkle
        case .leftShoulder:
            return .leftShoulder
        case .rightShoulder:
            return .rightShoulder
        }
    }
}
