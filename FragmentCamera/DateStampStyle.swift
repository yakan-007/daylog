import CoreGraphics

enum DateStampStyle {
    static let small = "small"
    static let medium = "medium"
    static let large = "large"

    static let allSizes = [small, medium, large]

    static func normalizedSizeKey(_ key: String) -> String {
        allSizes.contains(key) ? key : medium
    }

    static func scale(for key: String) -> CGFloat {
        switch normalizedSizeKey(key) {
        case small: return 0.82
        case large: return 1.24
        default: return 1.0
        }
    }

    static func fontSize(for renderSize: CGSize, sizeKey: String) -> CGFloat {
        let shortSide = min(renderSize.width, renderSize.height)
        // Portrait clips looked oversized with height-based sizing; use short side.
        return max(14, shortSide * 0.07 * scale(for: sizeKey))
    }

    static func topMargin(for renderSize: CGSize) -> CGFloat {
        let shortSide = min(renderSize.width, renderSize.height)
        return shortSide * 0.05
    }

    static func rightMargin(for renderSize: CGSize) -> CGFloat {
        let shortSide = min(renderSize.width, renderSize.height)
        return shortSide * 0.06
    }

    static func textHeight(for renderSize: CGSize, sizeKey: String) -> CGFloat {
        fontSize(for: renderSize, sizeKey: sizeKey) * 1.7
    }
}
