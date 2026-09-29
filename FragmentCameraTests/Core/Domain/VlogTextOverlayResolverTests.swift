import XCTest
@testable import FragmentCamera

final class VlogTextOverlayResolverTests: XCTestCase {
    func testResolveUsesCapturedMetadataWithoutMutatingIt() throws {
        let metadata = VlogClipSourceMetadata(
            capturedAt: Date(timeIntervalSince1970: 1_800_000_300),
            capturedPlaceName: "Shibuya",
            timeZoneIdentifier: "UTC"
        )
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            textOverlays: [
                VlogTextOverlay(source: .custom("A day out")),
                VlogTextOverlay(source: .capturedDate(format: .numeric)),
                VlogTextOverlay(source: .capturedTime(format: .twentyFourHour)),
                VlogTextOverlay(source: .place(customName: "Coffee shop"))
            ]
        )

        let resolved = VlogTextOverlayResolver.resolve(
            edit: edit,
            metadata: metadata,
            clipDuration: 5,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(resolved.map(\.text), [
            "A day out",
            "1/15/2027",
            "08:05",
            "Coffee shop"
        ])
        XCTAssertEqual(metadata.capturedPlaceName, "Shibuya")
    }

    func testResolveFallsBackToCapturedPlaceAndDropsUnavailablePlace() {
        let capturedPlaceEdit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            textOverlays: [VlogTextOverlay(source: .place(customName: nil))]
        )
        let captured = VlogTextOverlayResolver.resolve(
            edit: capturedPlaceEdit,
            metadata: VlogClipSourceMetadata(
                capturedAt: .distantPast,
                capturedPlaceName: "横浜",
                timeZoneIdentifier: "Asia/Tokyo"
            ),
            clipDuration: 3
        )
        let missing = VlogTextOverlayResolver.resolve(
            edit: capturedPlaceEdit,
            metadata: VlogClipSourceMetadata(
                capturedAt: .distantPast,
                capturedPlaceName: nil,
                timeZoneIdentifier: "Asia/Tokyo"
            ),
            clipDuration: 3
        )

        XCTAssertEqual(captured.map(\.text), ["横浜"])
        XCTAssertTrue(missing.isEmpty)
    }
}
