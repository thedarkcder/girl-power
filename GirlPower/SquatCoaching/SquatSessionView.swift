import SwiftUI

struct SquatSessionView: View {
    @StateObject private var viewModel: SquatSessionViewModel
    private let attemptIndex: Int
    private let onAttemptComplete: (SessionSummaryInput) -> Void
    @State private var isCompletingSet = false

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: SquatSessionViewModel())
        self.attemptIndex = 1
        self.onAttemptComplete = { _ in }
    }

    @MainActor
    init(viewModel: SquatSessionViewModel, attemptIndex: Int, onAttemptComplete: @escaping (SessionSummaryInput) -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.attemptIndex = attemptIndex
        self.onAttemptComplete = onAttemptComplete
    }

    @MainActor
    init(attemptIndex: Int, onAttemptComplete: @escaping (SessionSummaryInput) -> Void) {
        _viewModel = StateObject(wrappedValue: SquatSessionViewModel())
        self.attemptIndex = attemptIndex
        self.onAttemptComplete = onAttemptComplete
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SquatSessionControllerContainer(viewModel: viewModel)
                .ignoresSafeArea()
            overlay
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .alert(isPresented: Binding<Bool>(
            get: { viewModel.error != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.error = nil
                }
            }
        )) {
            Alert(
                title: Text("Session Error"),
                message: Text(viewModel.error?.localizedDescription ?? "Unknown"),
                dismissButton: .default(Text("OK"), action: { viewModel.error = nil })
            )
        }
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reps: \(viewModel.repCount)")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
            if let phaseLabel = phaseLabel {
                Text(phaseLabel)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
            }
            if !viewModel.statusText.isEmpty {
                Text(viewModel.statusText)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
            }
            Button(action: handleCompleteTapped) {
                Text(isCompletingSet ? "Preparing summary…" : "Complete Set")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .clipShape(Capsule())
                    .opacity(isCompletingSet ? 0.6 : 1)
            }
            .disabled(isCompletingSet)
            Spacer()
        }
        .padding(24)
    }

    private func handleCompleteTapped() {
        guard isCompletingSet == false else { return }
        isCompletingSet = true
        let input = viewModel.makeSummaryInput(attemptIndex: attemptIndex)
        onAttemptComplete(input)
    }

    private var phaseLabel: String? {
        switch viewModel.phase {
        case .idleWithinSet:
            return "Find your stance"
        case .descending:
            return "Descending"
        case .ascending:
            return "Ascending"
        case .repCompleted(let count, _):
            return "Rep \(count) completed"
        case .coachingPausedLowConfidence:
            return "Hold steady"
        }
    }
}

private struct SquatSessionControllerContainer: UIViewControllerRepresentable {
    let viewModel: SquatSessionViewModel

    func makeUIViewController(context: Context) -> SquatSessionViewController {
        let controller = SquatSessionViewController(coordinator: viewModel.coordinator)
        viewModel.bindOverlay(to: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: SquatSessionViewController, context: Context) {
        viewModel.bindOverlay(to: uiViewController)
    }
}

extension SquatSessionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Camera unavailable"
        case .permissionsDenied:
            return "Camera permission denied"
        case .configurationFailed(let message):
            return message
        case .captureFailed(let message):
            return message
        }
    }
}
