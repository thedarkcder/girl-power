import SwiftUI

struct DemoCTAView: View {
    @ObservedObject var viewModel: AppFlowViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 12) {
                Text("You're Ready")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.8))
                Text("Start your free momentum-building demo experience.")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            Button(action: { viewModel.startDemo() }) {
                Text(viewModel.demoButtonTitle)
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 32)
            .accessibilityIdentifier("start_demo_button")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hint)
            .disabled(viewModel.isDemoButtonDisabled)
            if let status = viewModel.demoStatusMessage {
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hint: String {
        switch viewModel.demoQuotaState {
        case .gatePending:
            return "Waiting for eligibility decision"
        case .locked(let reason):
            switch reason {
            case .quotaExhausted:
                return "Quota exhausted"
            case .evaluationDenied(let message):
                return message ?? "Quota denied"
            case .evaluationTimeout:
                return "Evaluation timed out"
            case .serverSync:
                return "Server sync required"
            }
        default:
            return "Routes to the Girl Power demo experience"
        }
    }
}

struct DemoCTAView_Previews: PreviewProvider {
    static var previews: some View {
        DemoCTAView(viewModel: AppFlowViewModel(
            repository: UserDefaultsOnboardingCompletionRepository(),
            demoQuotaCoordinator: DemoQuotaCoordinatorDisabled()
        ))
            .background(Color.black)
    }
}
