import AVFoundation
import XCTest
@testable import FragmentCamera

final class VlogTextLayerFactoryTests: XCTestCase {
    private func overlay(
        text: String,
        anchor: VlogNormalizedPoint,
        style: VlogTextStylePreset = .simple,
        scale: Double = 1,
        timeRange: VlogOverlayTimeRange = .entireClip
    ) -> VlogResolvedTextOverlay {
        VlogResolvedTextOverlay(
            id: UUID(),
            text: text,
            anchor: anchor,
            style: style,
            scale: scale,
            timeRange: timeRange
        )
    }

    func testLayerStaysInsideVideoContentFrameEvenAtTheCorner() {
        let contentFrame = CGRect(x: 100, y: 40, width: 800, height: 450)

        let layer = VlogTextLayerFactory.makeLayer(
            overlay: overlay(text: "A day in Tokyo", anchor: VlogNormalizedPoint(x: 1, y: 1), style: .band, scale: 1.2),
            contentFrame: contentFrame
        )

        XCTAssertGreaterThanOrEqual(layer.frame.minX, contentFrame.minX)
        XCTAssertLessThanOrEqual(layer.frame.maxX, contentFrame.maxX)
        XCTAssertGreaterThanOrEqual(layer.frame.minY, contentFrame.minY)
        XCTAssertLessThanOrEqual(layer.frame.maxY, contentFrame.maxY)
        XCTAssertNotNil(layer.backgroundColor, "帯の見た目は背景を持つ")
        let textLayer = layer.sublayers?.first as? CATextLayer
        XCTAssertEqual((textLayer?.string as? NSAttributedString)?.string, "A day in Tokyo")
    }

    func testLayerSizeMatchesTheSharedMeasurement() {
        let contentFrame = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let resolved = overlay(text: "東京に到着！！", anchor: .center, style: .bubble, scale: 1.5)

        let layer = VlogTextLayerFactory.makeLayer(overlay: resolved, contentFrame: contentFrame)
        let metrics = VlogTextMetrics.measure(overlay: resolved, contentFrame: contentFrame)

        XCTAssertEqual(layer.frame.width, metrics.boxSize.width, accuracy: 0.5)
        XCTAssertEqual(layer.frame.height, metrics.boxSize.height, accuracy: 0.5)
        XCTAssertEqual(layer.frame.midX, contentFrame.midX, accuracy: 0.5)
    }

    func testTimedLayerUsesClipOffsetAndSelectedRange() throws {
        let layers = VlogTextLayerFactory.makeTimedTextLayers(overlays: [
            TimedVlogTextOverlay(
                overlay: overlay(
                    text: "18:42",
                    anchor: .bottomLeading,
                    timeRange: VlogOverlayTimeRange(start: 1, end: 2.5)
                ),
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
