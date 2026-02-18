import Foundation

struct CoachingSpeechThrottle {
    let cooldown: TimeInterval
    private(set) var isSpeaking: Bool = false
    private(set) var lastFinishedAt: TimeInterval?

    init(cooldown: TimeInterval) {
        self.cooldown = cooldown
    }

    func canPlay(at time: TimeInterval) -> Bool {
        guard !isSpeaking else { return false }
        guard let lastFinishedAt else { return true }
        return time - lastFinishedAt >= cooldown
    }

    mutating func markStarted() {
        isSpeaking = true
    }

    mutating func markFinished(at time: TimeInterval) {
        isSpeaking = false
        lastFinishedAt = time
    }
}
