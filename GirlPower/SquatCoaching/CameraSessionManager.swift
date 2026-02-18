import AVFoundation
import UIKit

protocol CameraSessionManagerDelegate: AnyObject {
    func cameraSessionManager(_ manager: CameraSessionManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraSessionManager(_ manager: CameraSessionManager, didEncounter error: SquatSessionError)
    func cameraSessionManagerDidLosePermissions(_ manager: CameraSessionManager)
    func cameraSessionManager(_ manager: CameraSessionManager, wasInterrupted reason: SquatSessionInterruption)
    func cameraSessionManagerInterruptionEnded(_ manager: CameraSessionManager)
}

final class CameraSessionManager: NSObject {
    weak var delegate: CameraSessionManagerDelegate?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.girlpower.camera-session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false

    override init() {
        super.init()
        observeNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                    if !granted {
                        self.delegate?.cameraSessionManagerDidLosePermissions(self)
                    }
                }
            }
        case .denied, .restricted:
            completion(false)
            delegate?.cameraSessionManagerDidLosePermissions(self)
        @unknown default:
            completion(false)
            delegate?.cameraSessionManagerDidLosePermissions(self)
        }
    }

    func attachPreviewLayer(to view: UIView) {
        DispatchQueue.main.async {
            let layer = self.obtainPreviewLayer()
            layer.frame = view.bounds
            layer.videoGravity = .resizeAspectFill
            if layer.superlayer != view.layer {
                view.layer.insertSublayer(layer, at: 0)
            }
        }
    }

    func updatePreviewLayerFrame(_ frame: CGRect) {
        DispatchQueue.main.async {
            self.previewLayer?.frame = frame
        }
    }

    func startSession() {
        sessionQueue.async {
            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            } catch {
                self.delegate?.cameraSessionManager(self, didEncounter: .configurationFailed(error.localizedDescription))
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            throw SquatSessionError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        if session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        videoOutput.connections.first?.videoOrientation = .portrait
        session.commitConfiguration()
    }

    private func obtainPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let previewLayer {
            return previewLayer
        }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        return layer
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
    }

    @objc private func handleRuntimeError(_ notification: Notification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError {
            delegate?.cameraSessionManager(self, didEncounter: .captureFailed(error.localizedDescription))
        }
    }

    @objc private func handleWasInterrupted(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber,
              let reason = AVCaptureSession.InterruptionReason(rawValue: rawReason.intValue)
        else { return }
        delegate?.cameraSessionManager(self, wasInterrupted: reason.toSessionInterruption())
    }

    @objc private func handleInterruptionEnded(_ notification: Notification) {
        delegate?.cameraSessionManagerInterruptionEnded(self)
    }
}

extension CameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        delegate?.cameraSessionManager(self, didOutput: sampleBuffer)
    }
}

private extension AVCaptureSession.InterruptionReason {
    func toSessionInterruption() -> SquatSessionInterruption {
        switch self {
        case .audioDeviceInUseByAnotherClient:
            return .audioSession
        case .videoDeviceInUseByAnotherClient, .videoDeviceNotAvailableWithMultipleForegroundApps:
            return .captureRuntime
        case .videoDeviceNotAvailableInBackground:
            return .applicationBackgrounded
        default:
            return .other("reason_\(rawValue)")
        }
    }
}
