import XCTest
@testable import FragmentCamera

final class VlogTextOverlayResolverTests: XCTestCase {
    /// 2027-01-15 08:05 UTC
    private let capturedAt = Date(timeIntervalSince1970: 1_800_000_300)

    private func metadata(timeZone: String = "UTC") -> VlogClipSourceMetadata {
        VlogClipSourceMetadata(capturedAt: capturedAt, capturedPlaceName: "Shibuya", timeZoneIdentifier: timeZone)
    }

    func testBlockStacksDateTimePlaceAndCaptionInOrder() throws {
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            block: VlogStampBlock(
                showsDate: true,
                showsTime: true,
                showsPlace: true,
                placeName: "Coffee shop",
                caption: "A day out",
                anchor: .center
            ),
            sourceTimeZoneIdentifier: "UTC"
        )

        let resolved = VlogTextOverlayResolver.resolve(edit: edit, metadata: metadata(), clipDuration: 5)

        let overlay = try XCTUnwrap(resolved.first)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(overlay.text, "2027.1.15\n8:05\nCoffee shop\nA day out")
        XCTAssertEqual(overlay.alignment, .center)
        XCTAssertEqual(overlay.timeRange, .entireClip)
    }

    func testDateAndTimeUseTheStoredFormat() {
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            block: VlogStampBlock(showsDate: true, showsTime: true, zeroPadded: true, timeStyle: .twelveHour),
            sourceTimeZoneIdentifier: "UTC"
        )

        let resolved = VlogTextOverlayResolver.resolve(edit: edit, metadata: metadata(), clipDuration: 3)

        XCTAssertEqual(resolved.first?.text, "2027.01.15\n8:05 AM")
    }

    func testEditTimeZoneWinsOverPlaybackTimeZone() {
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            block: VlogStampBlock(showsTime: true),
            sourceTimeZoneIdentifier: "Asia/Tokyo"
        )

        let resolved = VlogTextOverlayResolver.resolve(edit: edit, metadata: metadata(), clipDuration: 3)

        XCTAssertEqual(resolved.first?.text, "17:05")
    }

    func testEmptyBlockResolvesToNothing() {
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            block: VlogStampBlock(showsPlace: true, placeName: " ", caption: "  ")
        )

        XCTAssertTrue(VlogTextOverlayResolver.resolve(edit: edit, metadata: metadata(), clipDuration: 3).isEmpty)
    }

    func testCaptionCanSitAboveTheDate() {
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            block: VlogStampBlock(showsDate: true, caption: "到着", captionPlacement: .above),
            sourceTimeZoneIdentifier: "UTC"
        )

        let resolved = VlogTextOverlayResolver.resolve(edit: edit, metadata: metadata(), clipDuration: 3)

        XCTAssertEqual(resolved.first?.text, "到着\n2027.1.15")
    }

    func testFadeOutShowsTwoSecondsThenFades() throws {
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            block: VlogStampBlock(showsTime: true, caption: "note", fadesOut: true),
            sourceTimeZoneIdentifier: "UTC"
        )

        let overlay = try XCTUnwrap(
            VlogTextOverlayResolver.resolve(edit: edit, metadata: metadata(), clipDuration: 4).first
        )

        XCTAssertEqual(overlay.timeRange, VlogOverlayTimeRange(start: 0, end: VlogFadeTiming.totalDuration))
        XCTAssertEqual(overlay.opacity(at: 1), 1)
        XCTAssertEqual(overlay.opacity(at: 2.25), 0.5, accuracy: 0.001)
        XCTAssertEqual(overlay.opacity(at: 3), 0)
    }

    func testShortClipsIgnoreTheFade() throws {
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            block: VlogStampBlock(showsTime: true, fadesOut: true),
            sourceTimeZoneIdentifier: "UTC"
        )

        let overlay = try XCTUnwrap(
            VlogTextOverlayResolver.resolve(edit: edit, metadata: metadata(), clipDuration: 2).first
        )

        XCTAssertEqual(overlay.timeRange, .entireClip)
        XCTAssertEqual(overlay.fadeOutDuration, 0)
    }
}
