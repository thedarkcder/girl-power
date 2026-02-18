import CoreGraphics
import Foundation

struct RepCounter {
    struct Configuration {
        let descentThreshold: CGFloat
        let releaseThreshold: CGFloat
        let minDwellTime: TimeInterval
        let minConfidence: CGFloat
        let smoothingAlpha: CGFloat
        let repCompletionHold: TimeInterval
        let invalidMotionGrace: TimeInterval
        let sampleResetInterval: TimeInterval

        static let `default` = Configuration(
            descentThreshold: 0.12,
            releaseThreshold: 0.04,
            minDwellTime: 0.18,
            minConfidence: 0.45,
            smoothingAlpha: 0.35,
            repCompletionHold: 0.25,
            invalidMotionGrace: 0.45,
            sampleResetInterval: 1.50
        )
    }

    struct Result: Equatable {
        let phase: PosePhase
        let repetitionCount: Int
        let cue: CoachingCue?
        let confidence: CGFloat
    }

    private let configuration: Configuration
    private var currentPhase: PosePhase = .idleWithinSet
    private var repCount: Int = 0
    private var smoothedDepth: CGFloat = 0
    private var dwellStart: TimeInterval?
    private var bottomReached = false
    private var lowConfidenceActive = false
    private var lastRepCompletionTimestamp: TimeInterval?
    private var lastSampleTimestamp: TimeInterval?

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    mutating func reset() {
        currentPhase = .idleWithinSet
        repCount = 0
        smoothedDepth = 0
        dwellStart = nil
        bottomReached = false
        lowConfidenceActive = false
        lastRepCompletionTimestamp = nil
        lastSampleTimestamp = nil
    }

    mutating func suspendForTrackingLoss() -> Result {
        let cue = emitLowConfidenceCueIfNeeded() ?? .correction(.lowConfidence)
        return result(for: currentPhase, cue: cue, confidence: 0)
    }

    var repetitionCount: Int {
        repCount
    }

    mutating func process(frame: PoseFrame) -> Result {
        var cue: CoachingCue?
        let timestamp = frame.timestamp

        if let lastTimestamp = lastSampleTimestamp,
           timestamp - lastTimestamp > configuration.sampleResetInterval {
            smoothedDepth = 0
            dwellStart = nil
            bottomReached = false
        }
        lastSampleTimestamp = timestamp

        guard let hipMid = frame.hipMidpoint,
              let kneeMid = frame.kneeMidpoint,
              let ankleMid = frame.ankleMidpoint
        else {
            cue = emitLowConfidenceCueIfNeeded()
            return result(for: .coachingPausedLowConfidence, cue: cue, confidence: 0)
        }

        let confidence = min(max(frame.averageLowerBodyConfidence, 0), 1)
        guard confidence >= configuration.minConfidence else {
            cue = emitLowConfidenceCueIfNeeded()
            return result(for: .coachingPausedLowConfidence, cue: cue, confidence: confidence)
        }

        if lowConfidenceActive {
            lowConfidenceActive = false
            // Restart from idle to avoid stale state after low-confidence gap.
            currentPhase = .idleWithinSet
            dwellStart = nil
            bottomReached = false
        }

        let hipDepth = max(hipMid.y - kneeMid.y, 0)
        let ankleBaselineDiff = max((ankleMid.y - kneeMid.y), 0.01)
        let normalizedDepth = hipDepth / ankleBaselineDiff

        smoothedDepth = configuration.smoothingAlpha * normalizedDepth + (1 - configuration.smoothingAlpha) * smoothedDepth
        let progress = clampedProgress(for: smoothedDepth)

        switch currentPhase {
        case .idleWithinSet:
            dwellStart = nil
            bottomReached = false
            if normalizedDepth >= configuration.descentThreshold {
                dwellStart = timestamp
                currentPhase = .descending(progress: progress)
            } else {
                currentPhase = .idleWithinSet
            }

        case .descending:
            if normalizedDepth >= configuration.descentThreshold {
                currentPhase = .descending(progress: progress)
                if dwellStart == nil { dwellStart = timestamp }
                if let dwellStart, timestamp - dwellStart >= configuration.minDwellTime {
                    bottomReached = true
                }
            } else {
                if bottomReached {
                    let ascendingCue = advanceAscendingPhase(
                        normalizedDepth: normalizedDepth,
                        timestamp: timestamp,
                        progress: progress
                    )
                    if cue == nil {
                        cue = ascendingCue
                    }
                } else if let dwellStart, timestamp - dwellStart >= configuration.invalidMotionGrace {
                    cue = .correction(.insufficientDepth)
                    currentPhase = .idleWithinSet
                    resetDescendingState()
                } else {
                    currentPhase = .idleWithinSet
                    resetDescendingState()
                }
            }

        case .ascending:
            let ascendingCue = advanceAscendingPhase(
                normalizedDepth: normalizedDepth,
                timestamp: timestamp,
                progress: progress
            )
            if cue == nil {
                cue = ascendingCue
            }

        case .repCompleted:
            if let hold = lastRepCompletionTimestamp, timestamp - hold >= configuration.repCompletionHold {
                currentPhase = .idleWithinSet
            } else {
                currentPhase = .repCompleted(repetitionCount: repCount, timestamp: holdTimestamp(for: timestamp))
            }

        case .coachingPausedLowConfidence:
            currentPhase = .idleWithinSet
            dwellStart = nil
            bottomReached = false
            if normalizedDepth >= configuration.descentThreshold {
                currentPhase = .descending(progress: progress)
                dwellStart = timestamp
            }
        }

        return result(for: currentPhase, cue: cue, confidence: confidence)
    }

    private mutating func emitLowConfidenceCueIfNeeded() -> CoachingCue? {
        defer { lowConfidenceActive = true }
        guard !lowConfidenceActive else { return nil }
        resetDescendingState()
        currentPhase = .coachingPausedLowConfidence
        return .correction(.lowConfidence)
    }

    private mutating func resetDescendingState() {
        dwellStart = nil
        bottomReached = false
    }

    private mutating func advanceAscendingPhase(
        normalizedDepth: CGFloat,
        timestamp: TimeInterval,
        progress: CGFloat
    ) -> CoachingCue? {
        if normalizedDepth <= configuration.releaseThreshold {
            repCount += 1
            currentPhase = .repCompleted(repetitionCount: repCount, timestamp: timestamp)
            lastRepCompletionTimestamp = timestamp
            resetDescendingState()
            return .positive
        } else {
            currentPhase = .ascending(progress: progress)
            return nil
        }
    }

    private func clampedProgress(for depth: CGFloat) -> CGFloat {
        let range = max(configuration.descentThreshold - configuration.releaseThreshold, 0.001)
        let normalized = (depth - configuration.releaseThreshold) / range
        return min(max(normalized, 0), 1)
    }

    private func holdTimestamp(for timestamp: TimeInterval) -> TimeInterval {
        lastRepCompletionTimestamp ?? timestamp
    }

    private func result(for phase: PosePhase, cue: CoachingCue?, confidence: CGFloat) -> Result {
        Result(phase: phase, repetitionCount: repCount, cue: cue, confidence: confidence)
    }
}
