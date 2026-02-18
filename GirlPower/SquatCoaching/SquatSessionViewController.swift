import UIKit

final class SquatSessionViewController: UIViewController {
    private let coordinator: SquatSessionCoordinator
    private let previewContainer = UIView()
    private let overlayView = LandmarkOverlayView()

    init(coordinator: SquatSessionCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewContainer.frame = view.bounds
        previewContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(previewContainer)
        overlayView.frame = view.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)
        coordinator.attachPreview(to: previewContainer)
        coordinator.overlayOutput = self
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        coordinator.updatePreviewFrame(view.bounds)
    }
}

extension SquatSessionViewController: SquatSessionCoordinatorOverlayOutput {
    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didUpdateOverlay frame: PoseFrame?, phase: PosePhase) {
        DispatchQueue.main.async {
            self.overlayView.poseFrame = frame
            self.overlayView.posePhase = phase
        }
    }
}
