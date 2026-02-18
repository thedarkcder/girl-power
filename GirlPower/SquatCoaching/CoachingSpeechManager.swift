import AVFoundation

protocol CoachingSpeechManaging: AnyObject {
    func enqueue(cue: CoachingCue)
    func stop()
}

final class CoachingSpeechManager: NSObject, CoachingSpeechManaging, @unchecked Sendable {
    struct Configuration {
        let cooldown: TimeInterval
        let positivePhrases: [String]
        let correctionPhrases: [CoachingCue.CorrectionReason: String]
        let voiceIdentifier: String?
        let rate: Float

        static let `default` = Configuration(
            cooldown: 3.0,
            positivePhrases: ["Great depth!", "Nice squat!", "Strong rep!"],
            correctionPhrases: [
                .insufficientDepth: "Drop your hips lower.",
                .instability: "Keep a steady pace.",
                .lowConfidence: "Step back into view."
            ],
            voiceIdentifier: nil,
            rate: AVSpeechUtteranceDefaultSpeechRate * 0.9
        )
    }

    private let configuration: Configuration
    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    private var throttle: CoachingSpeechThrottle
    private let queue = DispatchQueue(label: "com.girlpower.coaching-speech")

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.throttle = CoachingSpeechThrottle(cooldown: configuration.cooldown)
        super.init()
        synthesizer.delegate = self
        observeInterruptions()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func enqueue(cue: CoachingCue) {
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date().timeIntervalSince1970
            guard self.throttle.canPlay(at: now) else { return }
            self.prepareAudioSession()
            self.throttle.markStarted()
            let utterance = self.makeUtterance(for: cue)
            self.synthesizer.speak(utterance)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            self.deactivateAudioSession()
        }
    }

    private func prepareAudioSession() {
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true, options: [])
        } catch {
            // Non-fatal: speech will fail silently.
        }
    }

    private func deactivateAudioSession() {
        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Ignore
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: audioSession
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            stop()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Allow future utterances.
                    queue.async { [weak self] in
                        guard let self else { return }
                        self.throttle.markFinished(at: Date().timeIntervalSince1970)
                    }
                }
            }
        @unknown default:
            break
        }
    }

    private func makeUtterance(for cue: CoachingCue) -> AVSpeechUtterance {
        let phrase: String
        switch cue {
        case .positive:
            phrase = configuration.positivePhrases.randomElement() ?? "Great job!"
        case .correction(let reason):
            phrase = configuration.correctionPhrases[reason] ?? "Adjust your form."
        }
        let utterance = AVSpeechUtterance(string: phrase)
        if let identifier = configuration.voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        }
        utterance.rate = configuration.rate
        utterance.preUtteranceDelay = 0.05
        return utterance
    }
}

extension CoachingSpeechManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        queue.async { [weak self] in
            guard let self else { return }
            self.throttle.markFinished(at: Date().timeIntervalSince1970)
            if !self.synthesizer.isSpeaking {
                self.deactivateAudioSession()
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        queue.async { [weak self] in
            guard let self else { return }
            self.throttle.markFinished(at: Date().timeIntervalSince1970)
            if !self.synthesizer.isSpeaking {
                self.deactivateAudioSession()
            }
        }
    }
}
