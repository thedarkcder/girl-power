import Foundation
@testable import GirlPower

@MainActor
final class EntitlementServiceStub: ObservableObject, EntitlementServicing {
    @Published var state: EntitlementState
    var isPro: Bool
    private let stream: AsyncStream<EntitlementState>
    private let continuation: AsyncStream<EntitlementState>.Continuation

    init(initialState: EntitlementState = .loading, isPro: Bool = false) {
        self.state = initialState
        self.isPro = isPro
        var captured: AsyncStream<EntitlementState>.Continuation!
        self.stream = AsyncStream { continuation in
            captured = continuation
            continuation.yield(initialState)
        }
        self.continuation = captured
    }

    func load() async {}
    func purchase() async {}
    func restore() async {}

    func observeStates() -> AsyncStream<EntitlementState> {
        stream
    }

    func send(_ newState: EntitlementState, isPro: Bool) {
        state = newState
        self.isPro = isPro
        continuation.yield(newState)
    }
}
