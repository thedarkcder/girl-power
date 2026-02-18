import Foundation

struct SessionSummary: Equatable {
    enum TempoInsight: Equatable {
        case insufficientData
        case steady
        case needsControl
        case explosive

        var title: String {
            switch self {
            case .insufficientData:
                return "Need more reps"
            case .steady:
                return "Steady Tempo"
            case .needsControl:
                return "Slow It Down"
            case .explosive:
                return "Explosive Power"
            }
        }

        var subtitle: String {
            switch self {
            case .insufficientData:
                return "Complete at least one full rep to see tempo insights."
            case .steady:
                return "You maintained a consistent pace – keep stacking controlled reps."
            case .needsControl:
                return "Pace felt rushed. Focus on a smoother descent and hold at the bottom."
            case .explosive:
                return "Powerful intent detected. Maintain control on the way down."
            }
        }
    }

    struct CoachingNote: Equatable, Identifiable {
        let reason: CoachingCue.CorrectionReason
        let count: Int

        var id: String {
            reason.rawValue
        }

        var message: String {
            switch reason {
            case .insufficientDepth:
                return "Hit depth: squeeze your hips below your knees to lock the rep."
            case .instability:
                return "Stabilize: plant your feet and control the ascent."
            case .lowConfidence:
                return "Keep your body centered in frame for accurate tracking."
            }
        }
    }

    let attemptIndex: Int
    let totalReps: Int
    let tempoInsight: TempoInsight
    let averageTempoSeconds: TimeInterval?
    let coachingNotes: [CoachingNote]
    let duration: TimeInterval
    let generatedAt: Date
}

enum SummaryCTAState: Equatable {
    case awaitingDecision
    case secondAttemptEligible
    case locked(message: String)
    case proUnlocked

    var primaryButtonTitle: String {
        switch self {
        case .awaitingDecision:
            return "Checking eligibility…"
        case .secondAttemptEligible:
            return "One more go"
        case .locked:
            return "Continue to Paywall"
        case .proUnlocked:
            return "Start Coaching"
        }
    }
}

struct SummaryContext: Equatable {
    let summary: SessionSummary
    let ctaState: SummaryCTAState
}

struct SessionSummaryInput {
    let attemptIndex: Int
    let snapshot: RepCounter.Snapshot
    let duration: TimeInterval
    let generatedAt: Date
}

enum SessionSummaryFactory {
    static func make(from input: SessionSummaryInput) -> SessionSummary {
        let (insight, averageTempo) = tempoInsight(from: input.snapshot.tempoSamples)
        let notes = coachingNotes(from: input.snapshot.correctionCounts)
        return SessionSummary(
            attemptIndex: input.attemptIndex,
            totalReps: input.snapshot.repetitionCount,
            tempoInsight: insight,
            averageTempoSeconds: averageTempo,
            coachingNotes: notes,
            duration: input.duration,
            generatedAt: input.generatedAt
        )
    }

    private static func tempoInsight(from samples: [TimeInterval]) -> (SessionSummary.TempoInsight, TimeInterval?) {
        guard let average = average(samples) else {
            return (.insufficientData, nil)
        }
        switch average {
        case ..<1.0:
            return (.explosive, average)
        case 1.0..<2.0:
            return (.steady, average)
        default:
            return (.needsControl, average)
        }
    }

    private static func average(_ samples: [TimeInterval]) -> TimeInterval? {
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0, +)
        return total / Double(samples.count)
    }

    private static func coachingNotes(from counts: [CoachingCue.CorrectionReason: Int]) -> [SessionSummary.CoachingNote] {
        counts
            .filter { $0.value > 0 }
            .map { SessionSummary.CoachingNote(reason: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
}
