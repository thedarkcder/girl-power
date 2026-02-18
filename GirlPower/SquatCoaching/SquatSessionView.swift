import SwiftUI

struct SquatSessionView: View {
    @StateObject private var viewModel: SquatSessionViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: SquatSessionViewModel())
    }

    @MainActor
    init(viewModel: SquatSessionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
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
            Spacer()
        }
        .padding(24)
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
