import CoreGraphics
import Foundation

enum CaptureRotationPolicy {
    static func angle(
        closestTo horizonAngle: CGFloat,
        mode: CaptureOrientationMode
    ) -> CGFloat {
        let normalized = normalizedAngle(horizonAngle)
        let candidates: [CGFloat] = switch mode {
        case .portrait:
            [90, 270]
        }
        return candidates.min { lhs, rhs in
            circularDistance(from: normalized, to: lhs)
                < circularDistance(from: normalized, to: rhs)
        } ?? normalized
    }

    private static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        let remainder = angle.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private static func circularDistance(from lhs: CGFloat, to rhs: CGFloat) -> CGFloat {
        let difference = abs(lhs - rhs)
        return min(difference, 360 - difference)
    }
}
