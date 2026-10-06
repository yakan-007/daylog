import XCTest
@testable import FragmentCamera

final class VlogStampLayerSeederTests: XCTestCase {
    private func settings(
        isEnabled: Bool = true,
        position: DateStampPosition = .center,
        elements: Set<DateStampElement> = [.date, .time]
    ) -> DateStampSettings {
        DateStampSettings(
            isEnabled: isEnabled,
            format: DateStampFormatter.compactDateTime,
            isZeroPadded: true,
            timeStyle: .twelveHour,
            sizeKey: DateStampStyle.medium,
            position: position,
            elements: elements,
            fadesOut: false
        )
    }

    func testCopiesTheCommonStampAsIs() {
        let block = VlogStampLayerSeeder.block(settings: settings(), placeName: nil)

        XCTAssertTrue(block.showsDate)
        XCTAssertTrue(block.showsTime)
        XCTAssertFalse(block.showsPlace)
        XCTAssertTrue(block.zeroPadded)
        XCTAssertEqual(block.timeStyle, .twelveHour)
        XCTAssertEqual(block.anchor, VlogNormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(block.caption, "")
    }

    func testDisabledStampStartsEmptyButKeepsTheFormatAndPosition() {
        let block = VlogStampLayerSeeder.block(
            settings: settings(isEnabled: false, position: .bottomLeading),
            placeName: "渋谷区"
        )

        XCTAssertTrue(block.isEmpty)
        XCTAssertEqual(block.anchor, VlogNormalizedPoint(x: 0, y: 1))
        XCTAssertEqual(block.placeName, "渋谷区", "後から場所を出せるよう地名は持っておく")
    }

    func testPlaceIsShownOnlyWhenANameExists() {
        XCTAssertTrue(VlogStampLayerSeeder.block(settings: settings(elements: [.place]), placeName: "渋谷区").showsPlace)
        XCTAssertFalse(VlogStampLayerSeeder.block(settings: settings(elements: [.place]), placeName: "  ").showsPlace)
    }

    func testEveryPositionMapsToItsCorner() {
        XCTAssertEqual(VlogStampLayerSeeder.anchor(for: .topLeading), VlogNormalizedPoint(x: 0, y: 0))
        XCTAssertEqual(VlogStampLayerSeeder.anchor(for: .topTrailing), VlogNormalizedPoint(x: 1, y: 0))
        XCTAssertEqual(VlogStampLayerSeeder.anchor(for: .bottomLeading), VlogNormalizedPoint(x: 0, y: 1))
        XCTAssertEqual(VlogStampLayerSeeder.anchor(for: .bottomTrailing), VlogNormalizedPoint(x: 1, y: 1))
    }

    func testFadeSettingIsCarriedOver() {
        var common = settings()
        common.fadesOut = true
        XCTAssertTrue(VlogStampLayerSeeder.block(settings: common, placeName: nil).fadesOut)
    }
}
