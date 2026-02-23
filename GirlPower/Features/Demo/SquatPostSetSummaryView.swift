import SwiftUI

struct SquatPostSetSummaryView: View {
    @ObservedObject var viewModel: SquatPostSetSummaryViewModel
    let onStartNextAttempt: () -> Void
    let onContinueToPaywall: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                metrics
                tempoCard
                if viewModel.showCoachingNotes {
                    coachingNotes
                }
                actionButtons
            }
            .padding(24)
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set Complete")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            Text(viewModel.attemptTitle)
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metrics: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text(viewModel.repsLabel)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Text(viewModel.repsValue)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            VStack(alignment: .leading) {
                Text("Avg tempo")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Text(viewModel.averageTempoText)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.metricsAccessibilityLabel)
    }

    private var tempoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.tempoTitle)
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(viewModel.tempoSubtitle)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(viewModel.tempoTitle). \(viewModel.tempoSubtitle)")
    }

    private var coachingNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coaching Notes")
                .font(.headline)
                .foregroundColor(.white)
            ForEach(viewModel.coachingNotes) { note in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.message)
                            .font(.body)
                            .foregroundColor(.white)
                        Text("x\(note.count)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(note.message) repeated \(note.count) times")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: handlePrimaryAction) {
                Text(viewModel.primaryButtonTitle)
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .disabled(!viewModel.isPrimaryButtonEnabled)
            .opacity(viewModel.isPrimaryButtonEnabled ? 1 : 0.5)
            .accessibilityIdentifier("summary_primary_cta")
            .accessibilityHint(viewModel.primaryButtonHint)

            if viewModel.isSecondaryButtonVisible, let title = viewModel.secondaryButtonTitle {
                Button(action: onContinueToPaywall) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.6), lineWidth: 1)
                        )
                }
                .accessibilityIdentifier("summary_secondary_cta")
                .optionalAccessibilityHint(viewModel.secondaryButtonHint)
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .bottomLeading) {
            if let message = viewModel.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.top, 56)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func handlePrimaryAction() {
        switch viewModel.context.ctaState {
        case .secondAttemptEligible, .proUnlocked:
            onStartNextAttempt()
        case .locked:
            onContinueToPaywall()
        case .awaitingDecision:
            break
        }
    }
}

private extension View {
    @ViewBuilder
    func optionalAccessibilityHint(_ hint: String?) -> some View {
        if let hint {
            self.accessibilityHint(hint)
        } else {
            self
        }
    }
}

struct SquatPostSetSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        let summary = SessionSummary(
            attemptIndex: 1,
            totalReps: 6,
            tempoInsight: .steady,
            averageTempoSeconds: 1.3,
            coachingNotes: [
                SessionSummary.CoachingNote(reason: .instability, count: 2),
                SessionSummary.CoachingNote(reason: .insufficientDepth, count: 1)
            ],
            duration: 18,
            generatedAt: Date()
        )
        let context = SummaryContext(summary: summary, ctaState: .secondAttemptEligible)
        return SquatPostSetSummaryView(
            viewModel: SquatPostSetSummaryViewModel(context: context),
            onStartNextAttempt: {},
            onContinueToPaywall: {}
        )
        .background(Color.black)
    }
}
