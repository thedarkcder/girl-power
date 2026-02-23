import XCTest
@testable import GirlPower

@MainActor
final class SquatPostSetSummaryViewModelTests: XCTestCase {
    private func makeSummary(attemptIndex: Int = 1) -> SessionSummary {
        SessionSummary(
            attemptIndex: attemptIndex,
            totalReps: 4,
            tempoInsight: .steady,
            averageTempoSeconds: 1.2,
            coachingNotes: [],
            duration: 12,
            generatedAt: Date()
        )
    }

    func testSecondAttemptEligibleShowsSecondaryButton() {
        let context = SummaryContext(summary: makeSummary(), ctaState: .secondAttemptEligible)
        let viewModel = SquatPostSetSummaryViewModel(context: context)
        XCTAssertEqual(viewModel.primaryButtonTitle, "One more go")
        XCTAssertTrue(viewModel.isSecondaryButtonVisible)
        XCTAssertEqual(viewModel.secondaryButtonTitle, "Continue to Paywall")
        XCTAssertTrue(viewModel.isPrimaryButtonEnabled)
    }

    func testLockedStateDisablesSecondaryButtonAndShowsMessage() {
        let context = SummaryContext(summary: makeSummary(attemptIndex: 2), ctaState: .locked(message: "Denied"))
        let viewModel = SquatPostSetSummaryViewModel(context: context)
        XCTAssertEqual(viewModel.primaryButtonTitle, "Continue to Paywall")
        XCTAssertFalse(viewModel.isSecondaryButtonVisible)
        XCTAssertEqual(viewModel.statusMessage, "Denied")
    }

    func testAwaitingDecisionDisablesPrimaryButton() {
        let context = SummaryContext(summary: makeSummary(), ctaState: .awaitingDecision)
        let viewModel = SquatPostSetSummaryViewModel(context: context)
        XCTAssertFalse(viewModel.isPrimaryButtonEnabled)
        XCTAssertEqual(viewModel.statusMessage, "Eligibility decision pending. Hang tight…")
        XCTAssertEqual(viewModel.primaryButtonHint, "Waiting for the eligibility decision to finish.")
    }

    func testUpdateCTAStateRefreshesButtons() {
        let context = SummaryContext(summary: makeSummary(), ctaState: .awaitingDecision)
        let viewModel = SquatPostSetSummaryViewModel(context: context)
        viewModel.updateCTAState(.secondAttemptEligible)
        XCTAssertEqual(viewModel.primaryButtonTitle, "One more go")
        XCTAssertTrue(viewModel.isSecondaryButtonVisible)

        viewModel.updateCTAState(.locked(message: "Quota exhausted"))
        XCTAssertEqual(viewModel.primaryButtonTitle, "Continue to Paywall")
        XCTAssertFalse(viewModel.isSecondaryButtonVisible)
    }
}
