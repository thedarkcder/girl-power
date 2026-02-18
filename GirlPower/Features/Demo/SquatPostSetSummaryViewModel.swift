import Foundation

@MainActor
final class SquatPostSetSummaryViewModel: ObservableObject {
    @Published private(set) var context: SummaryContext

    init(context: SummaryContext) {
        self.context = context
    }

    func updateCTAState(_ state: SummaryCTAState) {
        guard context.ctaState != state else { return }
        context = SummaryContext(summary: context.summary, ctaState: state)
    }

    var attemptTitle: String {
        "Attempt #\(context.summary.attemptIndex)"
    }

    var primaryButtonTitle: String {
        context.ctaState.primaryButtonTitle
    }

    var primaryButtonHint: String {
        switch context.ctaState {
        case .awaitingDecision:
            return "Waiting for the eligibility decision to finish."
        case .secondAttemptEligible:
            return "Starts your second and final demo attempt."
        case .locked:
            return "Opens the paywall to continue."
        }
    }

    var secondaryButtonTitle: String? {
        switch context.ctaState {
        case .secondAttemptEligible:
            return "Continue to Paywall"
        default:
            return nil
        }
    }

    var secondaryButtonHint: String? {
        guard secondaryButtonTitle != nil else { return nil }
        return "Skips the second attempt and opens the paywall."
    }

    var isPrimaryButtonEnabled: Bool {
        switch context.ctaState {
        case .awaitingDecision:
            return false
        default:
            return true
        }
    }

    var isSecondaryButtonVisible: Bool {
        secondaryButtonTitle != nil
    }

    var repsLabel: String { "Reps completed" }

    var repsValue: String { "\(context.summary.totalReps)" }

    var metricsAccessibilityLabel: String {
        if context.summary.averageTempoSeconds == nil {
            return "\(repsValue) reps completed. Average tempo not available yet."
        }
        return "\(repsValue) reps completed. Average tempo \(averageTempoText)."
    }

    var tempoTitle: String { context.summary.tempoInsight.title }

    var tempoSubtitle: String { context.summary.tempoInsight.subtitle }

    var averageTempoText: String {
        guard let tempo = context.summary.averageTempoSeconds else {
            return "--"
        }
        return String(format: "%.1f s / rep", tempo)
    }

    var coachingNotes: [SessionSummary.CoachingNote] { context.summary.coachingNotes }

    var showCoachingNotes: Bool { !context.summary.coachingNotes.isEmpty }

    var statusMessage: String? {
        switch context.ctaState {
        case .awaitingDecision:
            return "Eligibility decision pending. Hang tight…"
        case .locked(let message):
            return message
        case .secondAttemptEligible:
            return "You can take one more demo attempt."
        }
    }
}
