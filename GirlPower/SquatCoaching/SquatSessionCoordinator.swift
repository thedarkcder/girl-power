import AVFoundation
import os
import UIKit

@MainActor
protocol SquatSessionCoordinatorOutput: AnyObject {
    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didTransitionTo state: SquatSessionStateMachine.State)
    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didUpdate result: RepCounter.Result)
    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didEncounter error: SquatSessionError)
}

@MainActor
protocol SquatSessionCoordinatorOverlayOutput: AnyObject {
    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didUpdateOverlay frame: PoseFrame?, phase: PosePhase)
}

final class SquatSessionCoordinator: NSObject {
    weak var output: SquatSessionCoordinatorOutput?
    weak var overlayOutput: SquatSessionCoordinatorOverlayOutput?

    private let stateMachine = SquatSessionStateMachine()
    private var currentState: SquatSessionStateMachine.State

    private let cameraManager: CameraSessionManager
    private let posePipeline: PoseDetectionPipeline
    private var repCounter: RepCounter
    private let speechManager: CoachingSpeechManaging
    private let logger = Logger(subsystem: "com.girlpower.app", category: "SquatSession")

    private var lifecycleObservers: [NSObjectProtocol] = []

    init(
        cameraManager: CameraSessionManager = CameraSessionManager(),
        posePipeline: PoseDetectionPipeline = PoseDetectionPipeline(),
        repCounter: RepCounter = RepCounter(),
        speechManager: CoachingSpeechManaging = CoachingSpeechManager()
    ) {
        self.cameraManager = cameraManager
        self.posePipeline = posePipeline
        self.repCounter = repCounter
        self.speechManager = speechManager
        self.currentState = stateMachine.initialState()
        super.init()
        self.cameraManager.delegate = self
        self.posePipeline.delegate = self
        observeLifecycle()
    }

    deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func start() {
        repCounter.reset()
        apply(event: .requestPermissions)
        cameraManager.requestPermissions { [weak self] granted in
            guard let self else { return }
            if granted {
                self.apply(event: .permissionsGranted)
                self.configureAndStartSession()
            } else {
                self.apply(event: .permissionsDenied)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.output?.squatSessionCoordinator(self, didEncounter: .permissionsDenied)
                }
            }
        }
    }

    func stop() {
        cameraManager.stopSession()
        posePipeline.cancel()
        speechManager.stop()
        repCounter.reset()
        apply(event: .sessionEnded)
    }

    func captureSummarySnapshot() -> RepCounter.Snapshot {
        cameraManager.stopSession()
        posePipeline.cancel()
        speechManager.stop()
        let snapshot = repCounter.snapshot()
        repCounter.reset()
        return snapshot
    }

    func presentSummary(_ context: SummaryContext) {
        apply(event: .summaryReady(context))
    }

    func attachPreview(to view: UIView) {
        cameraManager.attachPreviewLayer(to: view)
    }

    func updatePreviewFrame(_ frame: CGRect) {
        cameraManager.updatePreviewLayerFrame(frame)
    }

    private func configureAndStartSession() {
        apply(event: .configurationStarted)
        posePipeline.resume()
        cameraManager.startSession()
        apply(event: .configurationSucceeded())
    }

    private func handleLifecyclePause() {
        posePipeline.cancel()
        cameraManager.stopSession()
        apply(event: .enteredBackground)
    }

    private func handleLifecycleResume() {
        apply(event: .resumedForeground)
        configureAndStartSession()
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleLifecyclePause()
        })

        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleLifecycleResume()
        })
    }

    private func apply(event: SquatSessionStateMachine.Event) {
        let nextState = stateMachine.transition(from: currentState, event: event)
        currentState = nextState
        logger.debug("Transitioned to \(String(describing: nextState), privacy: .public) via \(String(describing: event), privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.output?.squatSessionCoordinator(self, didTransitionTo: nextState)
        }
    }
}

extension SquatSessionCoordinator: CameraSessionManagerDelegate {
    func cameraSessionManager(_ manager: CameraSessionManager, didOutput sampleBuffer: CMSampleBuffer) {
        posePipeline.process(sampleBuffer: sampleBuffer)
    }

    func cameraSessionManager(_ manager: CameraSessionManager, didEncounter error: SquatSessionError) {
        apply(event: .fatalError(error))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.output?.squatSessionCoordinator(self, didEncounter: error)
        }
    }

    func cameraSessionManagerDidLosePermissions(_ manager: CameraSessionManager) {
        apply(event: .permissionsDenied)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.output?.squatSessionCoordinator(self, didEncounter: .permissionsDenied)
        }
    }

    func cameraSessionManager(_ manager: CameraSessionManager, wasInterrupted reason: SquatSessionInterruption) {
        posePipeline.cancel()
        apply(event: .interruptionBegan(reason))
    }

    func cameraSessionManagerInterruptionEnded(_ manager: CameraSessionManager) {
        apply(event: .interruptionEnded)
        configureAndStartSession()
    }
}

extension SquatSessionCoordinator: PoseDetectionPipelineDelegate {
    func poseDetectionPipeline(_ pipeline: PoseDetectionPipeline, didDetect frame: PoseFrame) {
        let result = repCounter.process(frame: frame)
        let overlayFrame: PoseFrame?
        if case .coachingPausedLowConfidence = result.phase {
            overlayFrame = nil
        } else {
            overlayFrame = frame
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overlayOutput?.squatSessionCoordinator(self, didUpdateOverlay: overlayFrame, phase: result.phase)
        }
        apply(event: .posePhaseChanged(result.phase))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.output?.squatSessionCoordinator(self, didUpdate: result)
        }
        if let cue = result.cue {
            speechManager.enqueue(cue: cue)
            logger.debug("Played cue \(String(describing: cue), privacy: .public)")
        }
    }

    func poseDetectionPipelineDidLoseTracking(_ pipeline: PoseDetectionPipeline) {
        let result = repCounter.suspendForTrackingLoss()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overlayOutput?.squatSessionCoordinator(self, didUpdateOverlay: nil, phase: result.phase)
        }
        apply(event: .posePhaseChanged(result.phase))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.output?.squatSessionCoordinator(self, didUpdate: result)
        }
        if let cue = result.cue {
            speechManager.enqueue(cue: cue)
            logger.debug("Played cue \(String(describing: cue), privacy: .public)")
        }
    }

    func poseDetectionPipeline(_ pipeline: PoseDetectionPipeline, didFail error: Error) {
        apply(event: .fatalError(.captureFailed(error.localizedDescription)))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.output?.squatSessionCoordinator(self, didEncounter: .captureFailed(error.localizedDescription))
        }
        logger.error("Pose pipeline failed: \(error.localizedDescription, privacy: .public)")
    }
}
