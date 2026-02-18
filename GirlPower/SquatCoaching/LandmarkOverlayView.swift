import UIKit

final class LandmarkOverlayView: UIView {
    var poseFrame: PoseFrame? {
        didSet { setNeedsDisplay() }
    }

    var posePhase: PosePhase = .idleWithinSet {
        didSet { setNeedsDisplay() }
    }

    var overlayColor: UIColor = .systemPink

    private let jointRadius: CGFloat = 5

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.clear(rect)
        if let poseFrame {
            drawSkeleton(with: poseFrame, in: context)
            drawProgress(in: context, rect: rect)
        }
        if case .coachingPausedLowConfidence = posePhase {
            drawLowConfidenceBanner(in: rect, context: context)
        }
    }

    private func drawSkeleton(with frame: PoseFrame, in context: CGContext) {
        context.setStrokeColor(overlayColor.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(3)
        let segments: [(PoseJoint, PoseJoint)] = [
            (.leftHip, .leftKnee),
            (.rightHip, .rightKnee),
            (.leftKnee, .leftAnkle),
            (.rightKnee, .rightAnkle),
            (.leftHip, .rightHip),
            (.leftShoulder, .leftHip),
            (.rightShoulder, .rightHip)
        ]
        for (start, end) in segments {
            guard let startPoint = frame.point(start)?.position,
                  let endPoint = frame.point(end)?.position else { continue }
            context.move(to: convertToViewSpace(startPoint))
            context.addLine(to: convertToViewSpace(endPoint))
            context.strokePath()
        }

        context.setFillColor(overlayColor.withAlphaComponent(0.9).cgColor)
        PoseJoint.allCases.forEach { joint in
            guard let point = frame.point(joint)?.position else { return }
            let converted = convertToViewSpace(point)
            let circle = CGRect(
                x: converted.x - jointRadius,
                y: converted.y - jointRadius,
                width: jointRadius * 2,
                height: jointRadius * 2
            )
            context.fillEllipse(in: circle)
        }
    }

    private func drawProgress(in context: CGContext, rect: CGRect) {
        let barWidth: CGFloat = 8
        let inset: CGFloat = 16
        let barRect = CGRect(x: rect.width - barWidth - inset, y: inset, width: barWidth, height: rect.height - inset * 2)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(2)
        context.stroke(barRect)

        let progress: CGFloat
        switch posePhase {
        case .descending(let value), .ascending(let value):
            progress = value
        case .repCompleted:
            progress = 1
        default:
            progress = 0
        }
        guard progress > 0 else { return }
        context.setFillColor(overlayColor.cgColor)
        let filledHeight = barRect.height * progress
        let filledRect = CGRect(
            x: barRect.minX,
            y: barRect.maxY - filledHeight,
            width: barRect.width,
            height: filledHeight
        )
        context.fill(filledRect)
    }

    private func drawLowConfidenceBanner(in rect: CGRect, context: CGContext) {
        let message = "Move fully into frame"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let textSize = (message as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 12
        let bannerRect = CGRect(
            x: (rect.width - textSize.width - padding * 2) / 2,
            y: rect.height * 0.1,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )
        context.setFillColor(UIColor.black.withAlphaComponent(0.65).cgColor)
        let path = UIBezierPath(roundedRect: bannerRect, cornerRadius: 12)
        path.fill()
        let textRect = CGRect(
            x: bannerRect.origin.x + padding,
            y: bannerRect.origin.y + padding / 2,
            width: textSize.width,
            height: textSize.height
        )
        (message as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func convertToViewSpace(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * bounds.width, y: point.y * bounds.height)
    }
}
