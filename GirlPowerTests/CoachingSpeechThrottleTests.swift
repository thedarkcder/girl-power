import XCTest
@testable import GirlPower

final class CoachingSpeechThrottleTests: XCTestCase {
    func testCooldownPreventsOverlap() {
        var throttle = CoachingSpeechThrottle(cooldown: 3)
        XCTAssertTrue(throttle.canPlay(at: 0))
        throttle.markStarted()
        XCTAssertFalse(throttle.canPlay(at: 1))

        throttle.markFinished(at: 2)
        XCTAssertFalse(throttle.canPlay(at: 3.5))
        XCTAssertTrue(throttle.canPlay(at: 5.5))
    }

    func testInitialStateAllowsPlayback() {
        let throttle = CoachingSpeechThrottle(cooldown: 3)
        XCTAssertTrue(throttle.canPlay(at: 10))
        XCTAssertNil(throttle.lastFinishedAt)
        XCTAssertFalse(throttle.isSpeaking)
    }
}
