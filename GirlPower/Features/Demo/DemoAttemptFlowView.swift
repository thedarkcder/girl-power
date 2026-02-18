import SwiftUI

struct DemoAttemptFlowView: View {
    let attemptIndex: Int
    let onAttemptCompletion: (SessionSummaryInput) async -> SummaryContext
    let onExit: () -> Void
    @StateObject private var squatViewModel = SquatSessionViewModel()
    @State private var isCompletingSummary = false

    var body: some View {
        SquatSessionView(
            viewModel: squatViewModel,
            attemptIndex: attemptIndex,
            onAttemptComplete: handleAttemptCompletion(input:)
        )
            .navigationTitle("Squat Coaching")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onExit) {
                        Image(systemName: "chevron.left")
                        Text("Exit")
                    }
                    .accessibilityIdentifier("demo_toolbar_back_button")
                    .accessibilityHint("Returns to the Start Free Demo screen")
                    .disabled(isCompletingSummary)
                }
            }
            .navigationBarBackButtonHidden(true)
    }

    private func handleAttemptCompletion(input: SessionSummaryInput) {
        guard isCompletingSummary == false else { return }
        isCompletingSummary = true
        Task {
            let context = await onAttemptCompletion(input)
            await MainActor.run {
                squatViewModel.presentSummary(context)
                isCompletingSummary = false
            }
        }
    }
}

struct DemoAttemptFlowView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DemoAttemptFlowView(attemptIndex: 1, onAttemptCompletion: { input in
                SummaryContext(summary: SessionSummaryFactory.make(from: input), ctaState: .awaitingDecision)
            }, onExit: {})
        }
    }
}
