import SwiftUI

@main
struct GirlPowerApp: App {
    @StateObject private var viewModel: AppFlowViewModel
    private let quotaCoordinator: DemoQuotaCoordinating

    init() {
        let repository = UserDefaultsOnboardingCompletionRepository()
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetOnboarding") {
            repository.reset()
        }
        if arguments.contains("-returningUser") {
            repository.markCompleted()
        }
        let coordinator: DemoQuotaCoordinating
        if arguments.contains("-uiTesting") {
            coordinator = DemoQuotaCoordinatorDisabled()
        } else {
            coordinator = DemoQuotaDependenciesFactory.makeCoordinator()
        }
        self.quotaCoordinator = coordinator
        _viewModel = StateObject(wrappedValue: AppFlowViewModel(repository: repository, demoQuotaCoordinator: coordinator))
    }

    var body: some Scene {
        WindowGroup {
            AppFlowRootView(viewModel: viewModel)
        }
    }
}

struct AppFlowRootView: View {
    @ObservedObject var viewModel: AppFlowViewModel

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(backgroundStyle)
                .navigationDestination(for: AppFlowViewModel.Route.self) { route in
                    switch route {
                    case .demoStub:
                        DemoAttemptFlowView(
                            attemptIndex: viewModel.activeAttemptIndex,
                            onAttemptCompletion: { input in
                                await viewModel.completeAttempt(with: input)
                            },
                            onExit: { viewModel.finishDemo(reason: "toolbar_exit") }
                        )
                    case .paywall:
                        PaywallPlaceholderView(onClose: { viewModel.finishDemo(reason: "paywall_exit") })
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .splash:
            SplashView(onFinished: viewModel.handleSplashFinished)
        case .onboarding:
            OnboardingCarouselView(
                slides: viewModel.slides,
                currentIndex: viewModel.bindingForOnboardingIndex(),
                onComplete: viewModel.completeOnboarding
            )
        case .demoCTA, .demoStub:
            DemoCTAView(viewModel: viewModel)
        case .sessionSummary:
            if let summaryViewModel = viewModel.summaryViewModel {
                SquatPostSetSummaryView(
                    viewModel: summaryViewModel,
                    onStartSecondAttempt: viewModel.startSecondAttemptFromSummary,
                    onContinueToPaywall: viewModel.continueToPaywall
                )
            } else {
                DemoCTAView(viewModel: viewModel)
            }
        case .paywall:
            PaywallPlaceholderView(onClose: { viewModel.finishDemo(reason: "paywall_exit") })
        }
    }

    private var backgroundStyle: some View {
        Group {
            if case .splash = viewModel.state {
                Color.clear
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 0.05, green: 0.04, blue: 0.09), Color(red: 0.16, green: 0.08, blue: 0.21)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct PaywallPlaceholderView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Paywall Placeholder")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            Text("This is where the GP-117 paywall flow will appear.")
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: onClose) {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(32)
    }
}
