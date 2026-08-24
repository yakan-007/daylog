import Photos
import XCTest
@testable import FragmentCamera

final class DaylogStampAdjustmentTests: XCTestCase {
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

        let adjustment = try DaylogStampAdjustment.makePhotoAdjustment(context: context)

        XCTAssertTrue(DaylogStampAdjustment.canHandle(adjustment))
        XCTAssertEqual(try DaylogStampAdjustment.context(from: adjustment), context)
    }

    func testRejectsAdjustmentFromAnotherEditor() {
        let adjustment = PHAdjustmentData(
            formatIdentifier: "com.example.other",
            formatVersion: "1.0",
            data: Data()
        )

        XCTAssertFalse(DaylogStampAdjustment.canHandle(adjustment))
        XCTAssertThrowsError(try DaylogStampAdjustment.context(from: adjustment))
    }

}
