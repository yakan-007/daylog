import XCTest
@testable import FragmentCamera

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testUsesDocumentedDefaults() {
        let store = DaylogSettingsStore(defaults: defaults)

        XCTAssertTrue(store.stampEnabled)
        XCTAssertEqual(store.stampFormat, DateStampFormatter.compactDateTime)
        XCTAssertFalse(store.stampZeroPadded)
        XCTAssertEqual(store.stampTimeStyle, .twentyFourHour)
        XCTAssertEqual(store.stampSize, DateStampStyle.medium)
        XCTAssertEqual(store.stampPosition, .topTrailing)
        XCTAssertEqual(store.stampElements, [.date, .time])
        XCTAssertTrue(store.stampFadesOut)
        XCTAssertEqual(store.stampRenderingMode, .playbackOverlay)
        XCTAssertEqual(store.videoStorageMode, .standard)
        XCTAssertFalse(store.locationCaptureEnabled)
        XCTAssertEqual(store.selectedCaptureDuration, 3)
        XCTAssertFalse(store.hasSeenCaptureIntroCard)
        XCTAssertEqual(store.captureOrientationMode, .portrait)
    }

    func testNormalizesUnsupportedStoredValuesAtReadTime() {
        defaults.set("unsupported", forKey: "dateStampFormat")
        defaults.set("huge", forKey: "dateStampSize")
        defaults.set("unsupported", forKey: "dateStampPosition")
        defaults.set("unsupported", forKey: "dateStampTimeStyle")
        defaults.set("tiny", forKey: "videoStorageMode")
        defaults.set(42.0, forKey: "selectedCaptureDuration")
        defaults.set("diagonal", forKey: "captureOrientationMode")
        defaults.set("always", forKey: "dateStampRenderingMode")

        let store = DaylogSettingsStore(defaults: defaults)

        XCTAssertEqual(store.stampFormat, DateStampFormatter.compactDateTime)
        XCTAssertEqual(store.stampSize, DateStampStyle.medium)
        XCTAssertEqual(store.stampPosition, .topTrailing)
        XCTAssertEqual(store.stampTimeStyle, .twentyFourHour)
        XCTAssertEqual(store.videoStorageMode, .standard)
        XCTAssertEqual(store.selectedCaptureDuration, 3)
        XCTAssertEqual(store.captureOrientationMode, .portrait)
        XCTAssertEqual(store.stampRenderingMode, .playbackOverlay)
    }

    func testValuesPersistAcrossStoreInstances() {
        let first = DaylogSettingsStore(defaults: defaults)
        first.videoStorageMode = .compact
        first.locationCaptureEnabled = true
        first.selectedCaptureDuration = 5
        first.stampPosition = .bottomLeading
        first.stampTimeStyle = .twelveHour
        first.stampElements = [.time, .place]
        first.stampFadesOut = false
        first.stampRenderingMode = .burnOnCapture
        first.captureOrientationMode = .landscape

        let second = DaylogSettingsStore(defaults: defaults)

        XCTAssertEqual(second.videoStorageMode, .compact)
        XCTAssertTrue(second.locationCaptureEnabled)
        XCTAssertEqual(second.selectedCaptureDuration, 5)
        XCTAssertEqual(second.stampPosition, .bottomLeading)
        XCTAssertEqual(second.stampTimeStyle, .twelveHour)
        XCTAssertEqual(second.stampElements, [.time, .place])
        XCTAssertFalse(second.stampFadesOut)
        XCTAssertEqual(second.stampRenderingMode, .burnOnCapture)
        XCTAssertEqual(second.captureOrientationMode, .landscape)
    }

    func testEveryDurationShownByCaptureUIPersists() {
        for duration in CaptureDurationPolicy.options {
            let first = DaylogSettingsStore(defaults: defaults)
            first.selectedCaptureDuration = duration

            let second = DaylogSettingsStore(defaults: defaults)
            XCTAssertEqual(second.selectedCaptureDuration, duration)
        }
    }

    func testDisplayContextUsesCurrentSettingsAndKeepsCapturedMetadata() {
        let capturedAt = Date(timeIntervalSince1970: 1_784_000_000)
        let base = VideoPostProcessContext(
            stampEnabled: false,
            stampDate: capturedAt,
            format: DateStampFormatter.compactDateTime,
            zeroPadded: false,
            timeStyle: .twentyFourHour,
            sizeKey: DateStampStyle.small,
            position: .topTrailing,
            elements: [.time],
            fadesOut: false,
            placeName: "Shibuya",
            timeZoneIdentifier: "Asia/Tokyo",
            storageMode: .standard
        )
        let settings = DateStampSettings(
            isEnabled: true,
            format: DateStampFormatter.zeroPaddedDateTime,
            isZeroPadded: true,
            timeStyle: .twelveHour,
            sizeKey: DateStampStyle.large,
            position: .bottomTrailing,
            elements: [.date, .place],
            fadesOut: true
        )

        let context = settings.displayContext(
            basedOn: base,
            storageMode: .compact
        )

        XCTAssertEqual(context?.stampEnabled, true)
        XCTAssertEqual(context?.stampDate, capturedAt)
        XCTAssertEqual(context?.format, DateStampFormatter.zeroPaddedDateTime)
        XCTAssertEqual(context?.zeroPadded, true)
        XCTAssertEqual(context?.timeStyle, .twelveHour)
        XCTAssertEqual(context?.sizeKey, DateStampStyle.large)
        XCTAssertEqual(context?.position, .bottomTrailing)
        XCTAssertEqual(context?.elements, [.date, .place])
        XCTAssertEqual(context?.fadesOut, true)
        XCTAssertEqual(context?.placeName, "Shibuya")
        XCTAssertEqual(context?.timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(context?.storageMode, .compact)
    }

    func testDisabledDisplayContextRemovesStamp() {
        let settings = DateStampSettings(
            isEnabled: false,
            format: DateStampFormatter.compactDateTime,
            isZeroPadded: false,
            timeStyle: .twentyFourHour,
            sizeKey: DateStampStyle.medium,
            position: .center,
            elements: [.date, .time],
            fadesOut: true
        )
        let context = settings.displayContext(
            capturedAt: Date(timeIntervalSince1970: 1_784_000_000),
            placeName: nil,
            timeZoneIdentifier: "Asia/Tokyo",
            storageMode: .standard
        )

        XCTAssertNil(context)
    }

    func testRecordingContextKeepsMetadataWhileStampIsDisabled() {
        let capturedAt = Date(timeIntervalSince1970: 1_784_000_000)
        let settings = DateStampSettings(
            isEnabled: false,
            format: DateStampFormatter.compactDateTime,
            isZeroPadded: false,
            timeStyle: .twentyFourHour,
            sizeKey: DateStampStyle.medium,
            position: .center,
            elements: [.date, .place],
            fadesOut: true
        )

        let context = settings.recordingContext(
            capturedAt: capturedAt,
            placeName: "渋谷区",
            timeZoneIdentifier: "Asia/Tokyo",
            storageMode: .compact
        )

        XCTAssertFalse(context.stampEnabled)
        XCTAssertEqual(context.stampDate, capturedAt)
        XCTAssertEqual(context.placeName, "渋谷区")
        XCTAssertEqual(context.storageMode, .compact)
    }

    func testEveryPositionPassesThroughToExportContext() {
        for position in DateStampPosition.allCases {
            let settings = DateStampSettings(
                isEnabled: true,
                format: DateStampFormatter.compactDateTime,
                isZeroPadded: false,
                timeStyle: .twelveHour,
                sizeKey: DateStampStyle.medium,
                position: position,
                elements: [.date, .time],
                fadesOut: true
            )

            let context = settings.displayContext(
                capturedAt: Date(timeIntervalSince1970: 1_784_000_000),
                placeName: nil,
                timeZoneIdentifier: "Asia/Tokyo",
                storageMode: .standard
            )

            XCTAssertEqual(context?.position, position)
            XCTAssertEqual(context?.timeStyle, .twelveHour)
        }
    }

    func testPlaceNameIsResolvedWhenCurrentSettingsRequestItAndAssetHasLocation() {
        let settings = DateStampSettings(
            isEnabled: true,
            format: DateStampFormatter.compactDateTime,
            isZeroPadded: false,
            timeStyle: .twentyFourHour,
            sizeKey: DateStampStyle.medium,
            position: .bottomTrailing,
            elements: [.date, .place],
            fadesOut: false
        )

        XCTAssertTrue(settings.shouldResolvePlaceName(
            storedPlaceName: nil,
            hasAssetLocation: true
        ))
        XCTAssertTrue(settings.shouldResolvePlaceName(
            storedPlaceName: "   ",
            hasAssetLocation: true
        ))
        XCTAssertFalse(settings.shouldResolvePlaceName(
            storedPlaceName: "渋谷区",
            hasAssetLocation: true
        ))
        XCTAssertFalse(settings.shouldResolvePlaceName(
            storedPlaceName: nil,
            hasAssetLocation: false
        ))
    }

    func testPerVideoOverrideOnlyHidesContentAndKeepsCommonAppearance() {
        let settings = DateStampSettings(
            isEnabled: true,
            format: DateStampFormatter.compactDateTime,
            isZeroPadded: true,
            timeStyle: .twelveHour,
            sizeKey: DateStampStyle.large,
            position: .bottomTrailing,
            elements: [.date, .time, .place],
            fadesOut: false
        )

        let resolved = settings.applying(
            VideoStampVisibilityOverride(
                hidesStamp: false,
                hiddenElements: [.time, .place]
            )
        )

        XCTAssertTrue(resolved.isEnabled)
        XCTAssertEqual(resolved.elements, [.date])
        XCTAssertEqual(resolved.position, .bottomTrailing)
        XCTAssertEqual(resolved.sizeKey, DateStampStyle.large)
        XCTAssertEqual(resolved.timeStyle, .twelveHour)
        XCTAssertFalse(resolved.fadesOut)
    }

    func testPerVideoOverrideCanHideWholeStamp() {
        let store = DaylogSettingsStore(defaults: defaults)
        let resolved = store.dateStampSettings.applying(
            VideoStampVisibilityOverride(
                hidesStamp: true,
                hiddenElements: []
            )
        )

        XCTAssertFalse(resolved.isEnabled)
    }

}
