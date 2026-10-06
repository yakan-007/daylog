import AVFoundation
import XCTest
import UIKit
@testable import FragmentCamera

final class DateStampLayerFactoryTests: XCTestCase {
    func testTextLayerUsesVideoContentFrameInsteadOfLetterboxArea() {
        let contentFrame = CGRect(x: 300, y: 0, width: 480, height: 854)
        let layer = DateStampLayerFactory.makeTextLayer(
            contentFrame: contentFrame,
            context: makeContext(position: .bottomTrailing)
        )

        XCTAssertGreaterThanOrEqual(layer.frame.minX, contentFrame.minX)
        XCTAssertLessThanOrEqual(layer.frame.maxX, contentFrame.maxX)
        XCTAssertGreaterThanOrEqual(layer.frame.minY, contentFrame.minY)
        XCTAssertLessThanOrEqual(layer.frame.maxY, contentFrame.maxY)
        XCTAssertEqual(layer.alignmentMode, .right)
    }

    func testBurnLayerConvertsRequestedVerticalPlacementToCompositorCoordinates() {
        let contentFrame = CGRect(x: 0, y: 0, width: 720, height: 1280)
        let topLayer = DateStampLayerFactory.makeTextLayer(
            contentFrame: contentFrame,
            context: makeContext(position: .topTrailing)
        )
        let centerLayer = DateStampLayerFactory.makeTextLayer(
            contentFrame: contentFrame,
            context: makeContext(position: .center)
        )
        let bottomLayer = DateStampLayerFactory.makeTextLayer(
            contentFrame: contentFrame,
            context: makeContext(position: .bottomTrailing)
        )

        XCTAssertGreaterThan(topLayer.frame.minY, centerLayer.frame.minY)
        XCTAssertGreaterThan(centerLayer.frame.minY, bottomLayer.frame.minY)
        XCTAssertEqual(centerLayer.frame.midY, contentFrame.midY, accuracy: 1)
    }

    func testBurnLayerKeepsRequestedHorizontalAlignment() {
        let contentFrame = CGRect(x: 0, y: 0, width: 720, height: 1280)
        let leadingLayer = DateStampLayerFactory.makeTextLayer(
            contentFrame: contentFrame,
            context: makeContext(position: .bottomLeading)
        )
        let trailingLayer = DateStampLayerFactory.makeTextLayer(
            contentFrame: contentFrame,
            context: makeContext(position: .bottomTrailing)
        )
        let centerLayer = DateStampLayerFactory.makeTextLayer(
            contentFrame: contentFrame,
            context: makeContext(position: .center)
        )

        XCTAssertEqual(leadingLayer.alignmentMode, .left)
        XCTAssertEqual(trailingLayer.alignmentMode, .right)
        XCTAssertEqual(centerLayer.alignmentMode, .center)
    }

    func testEveryRequestedPositionGetsItsOwnPhysicalFrame() {
        let contentFrame = CGRect(x: 120, y: 80, width: 720, height: 1_280)
        let layers = Dictionary(uniqueKeysWithValues: DateStampPosition.allCases.map { position in
            (
                position,
                DateStampLayerFactory.makeTextLayer(
                    contentFrame: contentFrame,
                    context: makeContext(position: position)
                )
            )
        })
        let margin = DateStampStyle.margin(for: contentFrame.size)
        let left = try! XCTUnwrap(layers[.topLeading])
        let right = try! XCTUnwrap(layers[.topTrailing])
        let bottomLeft = try! XCTUnwrap(layers[.bottomLeading])
        let bottomRight = try! XCTUnwrap(layers[.bottomTrailing])
        let center = try! XCTUnwrap(layers[.center])

        XCTAssertEqual(left.frame.minX, contentFrame.minX + margin, accuracy: 1)
        XCTAssertEqual(bottomLeft.frame.minX, contentFrame.minX + margin, accuracy: 1)
        XCTAssertEqual(right.frame.maxX, contentFrame.maxX - margin, accuracy: 1)
        XCTAssertEqual(bottomRight.frame.maxX, contentFrame.maxX - margin, accuracy: 1)
        XCTAssertEqual(center.frame.midX, contentFrame.midX, accuracy: 1)
        XCTAssertGreaterThan(left.frame.midY, bottomLeft.frame.midY)
        XCTAssertGreaterThan(right.frame.midY, bottomRight.frame.midY)
        XCTAssertEqual(center.frame.midY, contentFrame.midY, accuracy: 1)
    }

    func testEveryRequestedPositionGetsItsOwnPhysicalFrameInLandscapeExport() {
        let contentFrame = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let layers = Dictionary(uniqueKeysWithValues: DateStampPosition.allCases.map { position in
            (
                position,
                DateStampLayerFactory.makeTextLayer(
                    contentFrame: contentFrame,
                    context: makeContext(position: position)
                )
            )
        })
        let margin = DateStampStyle.margin(for: contentFrame.size)
        let topLeft = try! XCTUnwrap(layers[.topLeading])
        let topRight = try! XCTUnwrap(layers[.topTrailing])
        let bottomLeft = try! XCTUnwrap(layers[.bottomLeading])
        let bottomRight = try! XCTUnwrap(layers[.bottomTrailing])
        let center = try! XCTUnwrap(layers[.center])

        XCTAssertEqual(topLeft.frame.minX, margin, accuracy: 1)
        XCTAssertEqual(bottomLeft.frame.minX, margin, accuracy: 1)
        XCTAssertEqual(topRight.frame.maxX, contentFrame.maxX - margin, accuracy: 1)
        XCTAssertEqual(bottomRight.frame.maxX, contentFrame.maxX - margin, accuracy: 1)
        XCTAssertGreaterThan(topLeft.frame.midY, bottomLeft.frame.midY)
        XCTAssertGreaterThan(topRight.frame.midY, bottomRight.frame.midY)
        XCTAssertEqual(center.frame.midX, contentFrame.midX, accuracy: 1)
        XCTAssertEqual(center.frame.midY, contentFrame.midY, accuracy: 1)
    }

    func testTimedLayersCoverEveryEnabledClipWithItsOwnInterval() throws {
        let context = makeContext(position: .bottomTrailing)
        let stamps = [
            TimedVideoStamp(
                context: context,
                start: .zero,
                duration: CMTime(seconds: 1, preferredTimescale: 600),
                contentFrame: CGRect(x: 0, y: 0, width: 720, height: 1_280)
            ),
            TimedVideoStamp(
                context: context,
                start: CMTime(seconds: 1, preferredTimescale: 600),
                duration: CMTime(seconds: 3, preferredTimescale: 600),
                contentFrame: CGRect(x: 0, y: 0, width: 720, height: 1_280)
            ),
            TimedVideoStamp(
                context: context,
                start: CMTime(seconds: 4, preferredTimescale: 600),
                duration: CMTime(seconds: 5, preferredTimescale: 600),
                contentFrame: CGRect(x: 0, y: 0, width: 720, height: 1_280)
            )
        ]

        let layers = DateStampLayerFactory.makeTimedTextLayers(stamps: stamps)

        XCTAssertEqual(layers.count, stamps.count)
        for (layer, stamp) in zip(layers, stamps) {
            let animation = try XCTUnwrap(
                layer.animation(forKey: "vlogish-stamp-visibility") as? CAKeyframeAnimation
            )
            XCTAssertEqual(
                animation.beginTime,
                AVCoreAnimationBeginTimeAtZero + stamp.start.seconds,
                accuracy: 0.000_001
            )
            XCTAssertEqual(animation.duration, stamp.duration.seconds, accuracy: 0.000_001)
            XCTAssertEqual(animation.fillMode, CAMediaTimingFillMode.forwards)
            XCTAssertFalse(animation.isRemovedOnCompletion)
        }
    }

    func testBurnLayerUsesSystemSemiboldFontReference() {
        let contentFrame = CGRect(x: 0, y: 0, width: 720, height: 1280)
        let layer = DateStampLayerFactory.makeTextLayer(
            contentFrame: contentFrame,
            context: makeContext(position: .center)
        )
        let expectedFont = UIFont.systemFont(
            ofSize: layer.fontSize,
            weight: .semibold
        )
        let font = layer.font as! CGFont

        XCTAssertEqual(font.postScriptName as String?, expectedFont.fontName)
    }

    private func makeContext(
        position: DateStampPosition
    ) -> VideoPostProcessContext {
        VideoPostProcessContext(
            stampEnabled: true,
            stampDate: Date(timeIntervalSince1970: 1_700_000_000),
            format: DateStampFormatter.compactDateTime,
            zeroPadded: false,
            timeStyle: .twentyFourHour,
            sizeKey: DateStampStyle.medium,
            position: position,
            elements: [.date, .time, .place],
            fadesOut: true,
            placeName: "渋谷区",
            timeZoneIdentifier: "Asia/Tokyo",
            storageMode: .standard
        )
    }
}
