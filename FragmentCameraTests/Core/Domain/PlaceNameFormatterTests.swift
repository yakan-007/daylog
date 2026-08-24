import XCTest
@testable import FragmentCamera

final class PlaceNameFormatterTests: XCTestCase {
    func testPrefersCityLevelName() {
        XCTAssertEqual(
            PlaceNameFormatter.string(
                locality: "渋谷区",
                subAdministrativeArea: nil,
                administrativeArea: "東京都",
                country: "日本"
            ),
            "渋谷区"
        )
    }

    func testFallsBackToAdministrativeArea() {
        XCTAssertEqual(
            PlaceNameFormatter.string(
                locality: nil,
                subAdministrativeArea: nil,
                administrativeArea: "北海道",
                country: "日本"
            ),
            "北海道"
        )
    }

    func testCollapsesWhitespaceAndNewlines() {
        XCTAssertEqual(
            PlaceNameFormatter.string(
                locality: "  New\nYork  ",
                subAdministrativeArea: nil,
                administrativeArea: nil,
                country: nil
            ),
            "New York"
        )
    }
}
