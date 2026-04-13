import SwiftUI

@MainActor
enum AppStartupWork {
    static func bootstrap(
        authService: any AuthServicing,
        entitlementService: any EntitlementServicing
    ) async {
        async let restoreSession: Void = authService.restoreSession()
        async let loadEntitlements: Void = entitlementService.load()
        _ = await (restoreSession, loadEntitlements)
    }
}

@main
struct GirlPowerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: AppFlowViewModel
    @StateObject private var entitlementService: StoreKitEntitlementService
    private let quotaCoordinator: DemoQuotaCoordinating

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let coordinator: DemoQuotaCoordinating
        if arguments.contains("-uiTesting") {
            coordinator = DemoQuotaCoordinatorDisabled()
        } else {
            coordinator = DemoQuotaDependenciesFactory.makeCoordinator()
        }
        let authService: any AuthServicing
        let profileService: any ProfileServicing
        let profileEntitlementSync: any ProfileEntitlementSyncing
        if arguments.contains("-uiTesting") {
            profileService = DisabledProfileService()
            profileEntitlementSync = DisabledProfileEntitlementSyncService()
            authService = DisabledAuthService()
        } else {
            let configuration = SupabaseProjectConfiguration.live()
            let anonymousSessionStore = UserDefaultsPendingAnonymousSessionStore()
            profileService = SupabaseProfileService(configuration: configuration)
            profileEntitlementSync = SupabaseProfileEntitlementSyncService(configuration: configuration)
            authService = SupabaseAuthService(
                api: SupabaseAuthRESTAPI(configuration: configuration),
                anonymousSessionStore: anonymousSessionStore,
                linker: SupabaseAnonymousSessionLinker(
                    configuration: configuration,
                    pendingStore: anonymousSessionStore
                ),
                profileService: profileService
            )
        }
        let repository = UserDefaultsOnboardingCompletionRepository(profileService: profileService)
        if arguments.contains("-resetOnboarding") {
            repository.reset()
        }
        if arguments.contains("-returningUser") {
            repository.markCompleted()
        }
        let entitlementService = StoreKitEntitlementService(
            productIDs: ["com.girlpower.app.pro.monthly"],
            profileEntitlementSync: profileEntitlementSync
        )
        self.quotaCoordinator = coordinator
        _entitlementService = StateObject(wrappedValue: entitlementService)
        _viewModel = StateObject(
            wrappedValue: AppFlowViewModel(
                repository: repository,
                demoQuotaCoordinator: coordinator,
                entitlementService: entitlementService,
                authService: authService
            )
        )
        Task {
            await AppStartupWork.bootstrap(
                authService: authService,
                entitlementService: entitlementService
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            AppFlowRootView(viewModel: viewModel)
                .onChange(of: scenePhase) { newPhase in
                    guard newPhase == .active else { return }
                    viewModel.handleAppDidBecomeActive()
                }
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
                .sheet(item: $viewModel.authPrompt) { prompt in
                    AuthGateView(viewModel: viewModel, prompt: prompt)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .interactiveDismissDisabled(viewModel.isAuthBusy)
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
