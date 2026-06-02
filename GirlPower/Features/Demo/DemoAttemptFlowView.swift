import SwiftUI

struct DemoAttemptFlowView: View {
    let attemptIndex: Int
    let onAttemptCompletion: (SessionSummaryInput) async -> SummaryContext
    let onExit: () -> Void
    @StateObject private var squatViewModel = SquatSessionViewModel()
    @State private var isCompletingSummary = false
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    var body: some View {
        content
            .navigationTitle("Squat Coaching")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: handleExit) {
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

    @ViewBuilder
    private var content: some View {
        if isUITesting {
            DemoEntryStubView()
        } else {
            SquatSessionView(
                viewModel: squatViewModel,
                attemptIndex: attemptIndex,
                onAttemptComplete: handleAttemptCompletion(input:)
            )
        }
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

    private func handleExit() {
        squatViewModel.stop()
        onExit()
    }
}

private struct DemoEntryStubView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "figure.strengthtraining.traditional")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .foregroundColor(.white)
            Text("Demo Preview")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            Text("This deterministic stub confirms the onboarding CTA routed into the guided squat coaching entry flow.")
                .font(.body)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("demo_stub_screen")
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
