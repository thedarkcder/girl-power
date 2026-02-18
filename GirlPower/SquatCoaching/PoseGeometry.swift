import CoreGraphics
import Foundation

enum PoseGeometry {
    static func angle(at vertex: CGPoint, from first: CGPoint, to second: CGPoint) -> CGFloat {
        let v1 = CGVector(dx: first.x - vertex.x, dy: first.y - vertex.y)
        let v2 = CGVector(dx: second.x - vertex.x, dy: second.y - vertex.y)
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let magnitude = (hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)).clamped(min: 0.0001)
        let cosine = max(min(dot / magnitude, 1), -1)
        return acos(cosine)
    }

    static func depthRatio(hip: CGPoint, knee: CGPoint, ankle: CGPoint) -> CGFloat {
        let hipToKnee = hip.y - knee.y
        let ankleToKnee = ankle.y - knee.y
        guard ankleToKnee != 0 else { return 0 }
        return max(min(hipToKnee / ankleToKnee, 1), 0)
    }
}

private extension CGFloat {
    func clamped(min: CGFloat) -> CGFloat {
        self < min ? min : self
    }
}
