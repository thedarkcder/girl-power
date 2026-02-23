import SwiftUI

@main
struct GirlPowerApp: App {
    @StateObject private var viewModel: AppFlowViewModel
    @StateObject private var entitlementService: StoreKitEntitlementService
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
        let entitlementService = StoreKitEntitlementService(productIDs: ["com.girlpower.app.pro.monthly"])
        self.quotaCoordinator = coordinator
        _entitlementService = StateObject(wrappedValue: entitlementService)
        _viewModel = StateObject(
            wrappedValue: AppFlowViewModel(
                repository: repository,
                demoQuotaCoordinator: coordinator,
                entitlementService: entitlementService
            )
        )
        Task {
            await entitlementService.load()
        }
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
                        PaywallView(
                            viewModel: PaywallViewModel(entitlementService: viewModel.paywallEntitlementService),
                            onClose: { viewModel.finishDemo(reason: "paywall_exit") }
                        )
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
                    onStartNextAttempt: viewModel.startNextAttemptFromSummary,
                    onContinueToPaywall: viewModel.continueToPaywall
                )
            } else {
                DemoCTAView(viewModel: viewModel)
            }
        case .paywall:
            PaywallView(
                viewModel: PaywallViewModel(entitlementService: viewModel.paywallEntitlementService),
                onClose: { viewModel.finishDemo(reason: "paywall_exit") }
            )
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
