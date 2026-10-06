import Photos
import XCTest
@testable import FragmentCamera

final class VlogishStampAdjustmentTests: XCTestCase {
    func testRoundTripsEveryEditableStampSetting() throws {
        let context = VideoPostProcessContext(
            stampEnabled: true,
            stampDate: Date(timeIntervalSince1970: 1_786_000_000),
            format: DateStampFormatter.compactDateTime,
            zeroPadded: true,
            timeStyle: .twelveHour,
            sizeKey: DateStampStyle.large,
            position: .bottomLeading,
            elements: [.date, .time, .place],
            fadesOut: false,
            placeName: "渋谷区",
            timeZoneIdentifier: "Asia/Tokyo",
            storageMode: .compact
        )

        let adjustment = try VlogishStampAdjustment.makePhotoAdjustment(context: context)

        XCTAssertTrue(VlogishStampAdjustment.canHandle(adjustment))
        XCTAssertEqual(try VlogishStampAdjustment.context(from: adjustment), context)
    }

    func testRejectsAdjustmentFromAnotherEditor() {
        let adjustment = PHAdjustmentData(
            formatIdentifier: "com.example.other",
            formatVersion: "1.0",
            data: Data()
        )

        XCTAssertFalse(VlogishStampAdjustment.canHandle(adjustment))
        XCTAssertThrowsError(try VlogishStampAdjustment.context(from: adjustment))
    }

}
