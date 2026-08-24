import AVFoundation
import XCTest
@testable import FragmentCamera

final class DaylogFailureTests: XCTestCase {
    func testPhotoPermissionMapsToSettingsRecovery() {
        let failure = DaylogFailureMapper.captureSaveFailure(
            from: AssetLibraryWriterError.permissionDenied
        )

        XCTAssertEqual(failure, .photoLibraryPermission)
        XCTAssertTrue(failure.requiresSettings)
    }

    func testCocoaOutOfSpaceErrorMapsToStorageFailure() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteOutOfSpaceError
        )

        XCTAssertEqual(
            DaylogFailureMapper.captureSaveFailure(from: error),
            .storageUnavailable
        )
        XCTAssertEqual(
            DaylogFailureMapper.exportFailure(from: error),
            .storageUnavailable
        )
    }

    func testPhotoKitExportFailureHasNetworkGuidance() {
        let failure = DaylogFailureMapper.exportFailure(
            from: DayVideoExporterError.photoKitUnavailable
        )

        XCTAssertEqual(failure, .libraryAssetUnavailable)
        XCTAssertTrue(failure.message.contains("通信状態"))
    }

    func testMissingRecordedAudioIsReportedWithoutSavingSilentVideo() {
        let failure = DaylogFailureMapper.captureSaveFailure(
            from: VideoPostProcessError.audioTrackMissing
        )

        XCTAssertEqual(failure, .audioRecordingUnavailable)
        XCTAssertEqual(failure.title, "音声を記録できませんでした")
        XCTAssertTrue(failure.message.contains("無音の動画は保存していません"))
    }

    func testOtherPostProcessErrorsMapToProcessingFailure() {
        XCTAssertEqual(
            DaylogFailureMapper.captureSaveFailure(
                from: VideoPostProcessError.videoTrackMissing
            ),
            .processingFailed
        )
    }

    func testExportCancellationHasRetryGuidance() {
        let failure = DaylogFailureMapper.exportFailure(
            from: DayVideoExporterError.cancelled
        )

        XCTAssertEqual(failure, .exportCancelled)
        XCTAssertTrue(failure.message.contains("もう一度"))
    }

    func testUnsupportedExporterHasSpecificFailure() {
        XCTAssertEqual(
            DaylogFailureMapper.exportFailure(from: MediaExporterError.unsupportedOutputType),
            .exportUnsupported
        )
    }

    func testLibraryPermissionFailureOpensSettingsRecovery() {
        let failure = DaylogFailureMapper.libraryFailure(
            from: PhotoLibraryRepositoryError.permissionDenied
        )

        XCTAssertEqual(failure, .photoLibraryReadPermission)
        XCTAssertTrue(failure.requiresSettings)
    }

    func testAVFoundationDiskFullErrorMapsToStorageFailure() {
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.Code.diskFull.rawValue
        )

        XCTAssertEqual(DaylogFailureMapper.exportFailure(from: error), .storageUnavailable)
    }

    func testStorageFailureDetailExplainsTemporaryWorkingSpace() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteOutOfSpaceError
        )

        let detail = DaylogFailureMapper.exportFailureDetail(from: error)

        XCTAssertTrue(detail.contains("空き容量が不足"))
        XCTAssertTrue(detail.contains("作業用ファイル"))
    }

    func testNestedOutOfSpaceErrorKeepsStorageCause() {
        let diskError = NSError(
            domain: NSPOSIXErrorDomain,
            code: 28
        )
        let wrapper = NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.Code.exportFailed.rawValue,
            userInfo: [NSUnderlyingErrorKey: diskError]
        )

        XCTAssertEqual(
            DaylogFailureMapper.exportFailure(from: wrapper),
            .storageUnavailable
        )
    }

    func testAssetCountMismatchDetailKeepsExpectedAndActualCounts() {
        let detail = DaylogFailureMapper.exportFailureDetail(
            from: DayVideoExporterError.assetCountMismatch(expected: 87, actual: 84)
        )

        XCTAssertTrue(detail.contains("予定87本"))
        XCTAssertTrue(detail.contains("84本"))
        XCTAssertTrue(detail.contains("不足3本"))
    }

    func testPhotoLibraryNetworkErrorHasSpecificGuidance() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)

        XCTAssertEqual(
            DaylogFailureMapper.exportFailure(from: error),
            .libraryAssetUnavailable
        )
        XCTAssertTrue(
            DaylogFailureMapper.exportFailureDetail(from: error).contains("iCloud")
        )
    }
}
