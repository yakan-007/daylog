import SwiftUI

enum PhotoSheetStyle {
    static let sectionSpacing: CGFloat = 12
    static let cardCornerRadius: CGFloat = 12
    static let headerCornerRadius: CGFloat = 12
    static let thumbnailShadowOpacity: Double = 0.14
    static let thumbnailStroke = Color.white.opacity(0.1)
    static let sectionHorizontalPadding: CGFloat = 10
    static let cardOverlayTint = Color.black.opacity(0.24)
    static let contentBottomInset: CGFloat = 108
}

extension View {
    func photoSheetCard(radius: CGFloat = PhotoSheetStyle.cardCornerRadius) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(PhotoSheetStyle.cardOverlayTint)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            )
    }
}
