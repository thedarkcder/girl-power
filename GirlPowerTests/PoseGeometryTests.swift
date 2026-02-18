import XCTest
@testable import GirlPower

final class PoseGeometryTests: XCTestCase {
    func testAngleCalculationMatchesRightAngle() {
        let vertex = CGPoint(x: 0, y: 0)
        let first = CGPoint(x: 1, y: 0)
        let second = CGPoint(x: 0, y: 1)
        let angle = PoseGeometry.angle(at: vertex, from: first, to: second)
        XCTAssertEqual(angle, .pi / 2, accuracy: 0.0001)
    }

    func testDepthRatioClampedBetweenZeroAndOne() {
        let hip = CGPoint(x: 0.5, y: 0.6)
        let knee = CGPoint(x: 0.5, y: 0.4)
        let ankle = CGPoint(x: 0.5, y: 0.9)
        let ratio = PoseGeometry.depthRatio(hip: hip, knee: knee, ankle: ankle)
        XCTAssertGreaterThan(ratio, 0)
        XCTAssertLessThan(ratio, 1)

        let hipAbove = CGPoint(x: 0.5, y: 0.1)
        let ratio2 = PoseGeometry.depthRatio(hip: hipAbove, knee: knee, ankle: ankle)
        XCTAssertEqual(ratio2, 0)
    }
}
