import XCTest
@testable import FragmentCamera

final class VlogClipEditTests: XCTestCase {
    func testCodableRoundTripPreservesRichTextSources() throws {
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            textOverlays: [
                VlogTextOverlay(source: .custom("夏休み\n最高 🎉")),
                VlogTextOverlay(source: .capturedDate(format: .full)),
                VlogTextOverlay(source: .capturedTime(format: .twentyFourHour)),
                VlogTextOverlay(source: .place(customName: "近所のカフェ"))
            ],
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let data = try JSONEncoder().encode(edit)
        let decoded = try JSONDecoder().decode(VlogClipEdit.self, from: data)

        XCTAssertEqual(decoded, edit)
    }

    func testNormalizationClampsLayoutAndTimeWithoutChangingText() throws {
        var style = VlogTextStyle.default
        style.relativeSize = 5
        style.outlineWidth = -2
        style.foregroundColor = VlogColor(red: -1, green: 0.4, blue: 3, alpha: 2)
        let id = UUID()
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            textOverlays: [
                VlogTextOverlay(
                    id: id,
                    source: .custom("  keep spacing  "),
                    anchor: VlogNormalizedPoint(x: -4, y: 8),
                    style: style,
                    timeRange: VlogOverlayTimeRange(start: -2, end: 30)
                )
            ]
        )

        let overlay = try XCTUnwrap(edit.normalized(for: 5).textOverlays.first)

        XCTAssertEqual(overlay.id, id)
        XCTAssertEqual(overlay.source, .custom("  keep spacing  "))
        XCTAssertEqual(overlay.anchor, VlogNormalizedPoint(x: 0, y: 1))
        XCTAssertEqual(overlay.timeRange, VlogOverlayTimeRange(start: 0, end: 5))
        XCTAssertEqual(overlay.style.relativeSize, 2)
        XCTAssertEqual(overlay.style.outlineWidth, 0)
        XCTAssertEqual(
            overlay.style.foregroundColor,
            VlogColor(red: 0, green: 0.4, blue: 1, alpha: 1)
        )
    }

    func testNormalizationRemovesBlankInvalidAndDuplicateOverlays() {
        let duplicateID = UUID()
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            textOverlays: [
                VlogTextOverlay(source: .custom(" \n ")),
                VlogTextOverlay(
                    id: duplicateID,
                    source: .custom("first"),
                    timeRange: VlogOverlayTimeRange(start: 1, end: 3)
                ),
                VlogTextOverlay(
                    id: duplicateID,
                    source: .custom("duplicate"),
                    timeRange: VlogOverlayTimeRange(start: 0, end: 2)
                ),
                VlogTextOverlay(
                    source: .custom("invalid range"),
                    timeRange: VlogOverlayTimeRange(start: 4, end: 2)
                )
            ]
        )

        let normalized = edit.normalized(for: 5)

        XCTAssertEqual(normalized.textOverlays.count, 1)
        XCTAssertEqual(normalized.textOverlays.first?.source, .custom("first"))
    }

    func testPlaceOverrideDoesNotReplaceCapturedPlace() {
        let captured = VlogTextSource.place(customName: nil)
        let overridden = VlogTextSource.place(customName: "駅前")

        XCTAssertEqual(captured.resolvedPlaceName(capturedPlaceName: "渋谷区"), "渋谷区")
        XCTAssertEqual(overridden.resolvedPlaceName(capturedPlaceName: "渋谷区"), "駅前")
    }

    func testActiveOverlaysUseHalfOpenTimeRange() {
        let first = VlogTextOverlay(
            source: .custom("first"),
            timeRange: VlogOverlayTimeRange(start: 0, end: 2)
        )
        let second = VlogTextOverlay(
            source: .custom("second"),
            timeRange: VlogOverlayTimeRange(start: 2, end: 4)
        )
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            textOverlays: [first, second]
        )

        XCTAssertEqual(edit.activeTextOverlays(at: 1.999).map(\.source), [.custom("first")])
        XCTAssertEqual(edit.activeTextOverlays(at: 2).map(\.source), [.custom("second")])
    }
}
