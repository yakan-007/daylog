import AVFoundation
import XCTest
@testable import FragmentCamera

final class VlogishFailureTests: XCTestCase {
    func testPhotoPermissionMapsToSettingsRecovery() {
        let failure = VlogishFailureMapper.captureSaveFailure(
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
            VlogishFailureMapper.captureSaveFailure(from: error),
            .storageUnavailable
        )
        XCTAssertEqual(
            VlogishFailureMapper.exportFailure(from: error),
            .storageUnavailable
        )
    }

    func testPhotoKitExportFailureHasNetworkGuidance() {
        let failure = VlogishFailureMapper.exportFailure(
            from: DayVideoExporterError.photoKitUnavailable
        )

        XCTAssertEqual(failure, .libraryAssetUnavailable)
        XCTAssertTrue(failure.message.contains("通信状態"))
    }

    func testMissingRecordedAudioIsReportedWithoutSavingSilentVideo() {
        let failure = VlogishFailureMapper.captureSaveFailure(
            from: VideoPostProcessError.audioTrackMissing
        )

        XCTAssertEqual(failure, .audioRecordingUnavailable)
        XCTAssertEqual(failure.title, "音声を記録できませんでした")
        XCTAssertTrue(failure.message.contains("無音の動画は保存していません"))
    }

    func testOtherPostProcessErrorsMapToProcessingFailure() {
        XCTAssertEqual(
            VlogishFailureMapper.captureSaveFailure(
                from: VideoPostProcessError.videoTrackMissing
            ),
            .processingFailed
        )
    }

    func testExportCancellationHasRetryGuidance() {
        let failure = VlogishFailureMapper.exportFailure(
            from: DayVideoExporterError.cancelled
        )

        XCTAssertEqual(failure, .exportCancelled)
        XCTAssertTrue(failure.message.contains("もう一度"))
    }

    func testUnsupportedExporterHasSpecificFailure() {
        XCTAssertEqual(
            VlogishFailureMapper.exportFailure(from: MediaExporterError.unsupportedOutputType),
            .exportUnsupported
        )
    }

    func testLibraryPermissionFailureOpensSettingsRecovery() {
        let failure = VlogishFailureMapper.libraryFailure(
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

        XCTAssertEqual(VlogishFailureMapper.exportFailure(from: error), .storageUnavailable)
    }

    func testStorageFailureDetailExplainsTemporaryWorkingSpace() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteOutOfSpaceError
        )

        let detail = VlogishFailureMapper.exportFailureDetail(from: error)

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
            VlogishFailureMapper.exportFailure(from: wrapper),
            .storageUnavailable
        )
    }

    func testAssetCountMismatchDetailKeepsExpectedAndActualCounts() {
        let detail = VlogishFailureMapper.exportFailureDetail(
            from: DayVideoExporterError.assetCountMismatch(expected: 87, actual: 84)
        )

        XCTAssertTrue(detail.contains("予定87本"))
        XCTAssertTrue(detail.contains("84本"))
        XCTAssertTrue(detail.contains("不足3本"))
    }

    func testPhotoLibraryNetworkErrorHasSpecificGuidance() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)

        XCTAssertEqual(
            VlogishFailureMapper.exportFailure(from: error),
            .libraryAssetUnavailable
        )
        XCTAssertTrue(
            VlogishFailureMapper.exportFailureDetail(from: error).contains("iCloud")
        )
    }
}
