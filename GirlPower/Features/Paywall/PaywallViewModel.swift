import Foundation

@MainActor
final class PaywallViewModel: ObservableObject {
    @Published private(set) var state: EntitlementState

    let privacyURL: URL
    let termsURL: URL
    let featureBullets: [String]

    private let entitlementService: EntitlementServicing
    private var stateTask: Task<Void, Never>?

    init(
        entitlementService: EntitlementServicing,
        privacyURL: URL = URL(string: "https://girlpower.ai/privacy")!,
        termsURL: URL = URL(string: "https://girlpower.ai/terms")!,
        featureBullets: [String] = [
            "Unlimited AI-powered squat coaching",
            "Personalized cues every rep",
            "Session history & insights"
        ]
    ) {
        self.entitlementService = entitlementService
        self.privacyURL = privacyURL
        self.termsURL = termsURL
        self.featureBullets = featureBullets
        self.state = entitlementService.state
        observeStates()
    }

    deinit {
        stateTask?.cancel()
    }

    func subscribe() {
        Task { await entitlementService.purchase() }
    }

    func restore() {
        Task { await entitlementService.restore() }
    }

    func retryLoad() {
        Task { await entitlementService.load() }
    }

    var titleText: String {
        state.paywallProduct?.displayName ?? "Girl Power Coaching"
    }

    var priceText: String {
        state.paywallProduct?.pricePerPeriodDescription ?? "--"
    }

    var isProcessing: Bool {
        switch state {
        case .loading, .purchasing, .restoring:
            return true
        default:
            return false
        }
    }

    var errorMessage: String? {
        if case .error(let message, _) = state {
            return message
        }
        return nil
    }

    var successMessage: String? {
        state.isSubscribed ? "You're all set! Unlimited coaching unlocked." : nil
    }

    var isSubscribeDisabled: Bool {
        state.paywallProduct == nil || isProcessing || state.isSubscribed
    }

    var isRestoreDisabled: Bool {
        isProcessing || state.isSubscribed
    }

    private func observeStates() {
        stateTask = Task {
            for await newState in entitlementService.observeStates() {
                await MainActor.run {
                    self.state = newState
                }
            }
        }
    }
}
