import SwiftUI

@main
struct GirlPowerApp: App {
    @StateObject private var viewModel: AppFlowViewModel

    init() {
        let repository = UserDefaultsOnboardingCompletionRepository()
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetOnboarding") {
            repository.reset()
        }
        if arguments.contains("-returningUser") {
            repository.markCompleted()
        }
        _viewModel = StateObject(wrappedValue: AppFlowViewModel(repository: repository))
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
                        DemoAttemptFlowView(onExit: viewModel.finishDemo)
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
            DemoCTAView(onStartDemo: viewModel.startDemo)
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
