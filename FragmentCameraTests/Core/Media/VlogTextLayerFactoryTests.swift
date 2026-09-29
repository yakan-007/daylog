import AVFoundation
import XCTest
@testable import FragmentCamera

final class VlogTextLayerFactoryTests: XCTestCase {
    func testTextLayerStaysInsideVideoContentFrame() {
        let contentFrame = CGRect(x: 100, y: 40, width: 800, height: 450)
        let overlay = VlogResolvedTextOverlay(
            id: UUID(),
            text: "A day in Tokyo",
            anchor: .bottomTrailing,
            style: VlogTextStyle(
                fontDesign: .rounded,
                fontWeight: .bold,
                relativeSize: 1.2,
                alignment: .trailing,
                foregroundColor: .white,
                backgroundColor: VlogColor(red: 0, green: 0, blue: 0, alpha: 0.6),
                outlineColor: nil,
                outlineWidth: 0
            ),
            timeRange: .entireClip
        )

        let layer = VlogTextLayerFactory.makeTextLayer(
            overlay: overlay,
            contentFrame: contentFrame
        )

        XCTAssertGreaterThanOrEqual(layer.frame.minX, contentFrame.minX)
        XCTAssertLessThanOrEqual(layer.frame.maxX, contentFrame.maxX)
        XCTAssertGreaterThanOrEqual(layer.frame.minY, contentFrame.minY)
        XCTAssertLessThanOrEqual(layer.frame.maxY, contentFrame.maxY)
        XCTAssertEqual(layer.alignmentMode, .right)
        XCTAssertEqual(layer.string as? String, "A day in Tokyo")
    }

    func testTimedLayerUsesClipOffsetAndSelectedRange() throws {
        let overlay = VlogResolvedTextOverlay(
            id: UUID(),
            text: "18:42",
            anchor: .bottomLeading,
            style: .default,
            timeRange: VlogOverlayTimeRange(start: 1, end: 2.5)
        )
        let layers = VlogTextLayerFactory.makeTimedTextLayers(overlays: [
            TimedVlogTextOverlay(
                overlay: overlay,
                start: CMTime(seconds: 5, preferredTimescale: 600),
                duration: CMTime(seconds: 1.5, preferredTimescale: 600),
                contentFrame: CGRect(x: 0, y: 0, width: 1080, height: 1920)
            )
        ])

        XCTAssertEqual(layers.count, 1)
        let animation = try XCTUnwrap(
            layers[0].animation(forKey: "vlogish-text-visibility")
        )
        XCTAssertEqual(animation.beginTime, AVCoreAnimationBeginTimeAtZero + 5, accuracy: 0.001)
        XCTAssertEqual(animation.duration, 1.5, accuracy: 0.001)
    }
}
