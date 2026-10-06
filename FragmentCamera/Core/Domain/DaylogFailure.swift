import AVFoundation
import Foundation

enum VlogishFailure: String, Identifiable, Equatable, Sendable {
    case photoLibraryPermission
    case photoLibraryReadPermission
    case storageUnavailable
    case recordingFailed
    case audioRecordingUnavailable
    case unsavedCaptureAvailable
    case processingFailed
    case saveFailed
    case noExportAssets
    case libraryAssetUnavailable
    case exportUnsupported
    case exportCancelled
    case exportFailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photoLibraryPermission, .photoLibraryReadPermission:
            return L10n.text("写真へのアクセスが必要です")
        case .storageUnavailable:
            return L10n.text("空き容量を確認してください")
        case .recordingFailed:
            return L10n.text("録画を完了できませんでした")
        case .audioRecordingUnavailable:
            return L10n.text("音声を記録できませんでした")
        case .unsavedCaptureAvailable:
            return L10n.text("未保存の動画があります")
        case .processingFailed, .saveFailed:
            return L10n.text("保存できませんでした")
        case .noExportAssets:
            return L10n.text("動画が見つかりません")
        case .libraryAssetUnavailable:
            return L10n.text("動画を読み込めませんでした")
        case .exportUnsupported:
            return L10n.text("この端末では結合できません")
        case .exportCancelled:
            return L10n.text("結合を中断しました")
        case .exportFailed:
            return L10n.text("結合に失敗しました")
        }
    }

    var message: String {
        switch self {
        case .photoLibraryPermission:
            return L10n.text("写真へのアクセスを許可すると、次回から動画を保存できます。今回の動画は保存されませんでした。")
        case .photoLibraryReadPermission:
            return L10n.text("写真へのアクセスを許可すると、「%@」アルバムの動画を一覧・再生・結合できます。", AppIdentity.photoAlbumName)
        case .storageUnavailable:
            return L10n.text("端末の空き容量を増やしてから、もう一度お試しください。")
        case .recordingFailed:
            return L10n.text("カメラの状態を確認して、もう一度撮影してください。")
        case .audioRecordingUnavailable:
            return L10n.text("マイクを使用できる状態か確認して、もう一度撮影してください。無音の動画は保存していません。")
        case .unsavedCaptureAvailable:
            return L10n.text("前回の保存処理が完了しなかった可能性があります。撮影原本を書き出して救出するか、不要なら削除してください。")
        case .processingFailed:
            return L10n.text("動画の仕上げ処理に失敗しました。もう一度撮影してください。")
        case .saveFailed:
            return L10n.text("動画を写真ライブラリへ保存できませんでした。もう一度撮影してください。")
        case .noExportAssets:
            return L10n.text("結合できる動画が見つかりませんでした。ライブラリを更新してからお試しください。")
        case .libraryAssetUnavailable:
            return L10n.text("iCloud上の動画を取得できない可能性があります。通信状態を確認して、もう一度お試しください。")
        case .exportUnsupported:
            return L10n.text("利用できる動画形式が見つかりませんでした。保存容量を「標準」に変えて、もう一度お試しください。")
        case .exportCancelled:
            return L10n.text("アプリがバックグラウンドになったか、処理が中断されました。アプリを開いたまま、もう一度お試しください。")
        case .exportFailed:
            return L10n.text("動画を書き出せませんでした。通信状態と空き容量を確認して、もう一度お試しください。")
        }
    }

    var requiresSettings: Bool {
        self == .photoLibraryPermission || self == .photoLibraryReadPermission
    }
}

enum VlogishFailureMapper {
    static func captureSaveFailure(from error: Error) -> VlogishFailure {
        if case VideoPostProcessError.audioTrackMissing = error {
            return .audioRecordingUnavailable
        }
        if case AssetLibraryWriterError.permissionDenied = error {
            return .photoLibraryPermission
        }
        if isStorageUnavailable(error) || error is TemporaryFileStoreError {
            return .storageUnavailable
        }
        if error is VideoPostProcessError || error is MediaExporterError {
            return .processingFailed
        }
        return .saveFailed
    }

    static func exportFailure(from error: Error) -> VlogishFailure {
        if isStorageUnavailable(error) || error is TemporaryFileStoreError {
            return .storageUnavailable
        }
        if isPhotoLibraryUnavailable(error) {
            return .libraryAssetUnavailable
        }
        if let exporterError = error as? DayVideoExporterError {
            switch exporterError {
            case .noAssets:
                return .noExportAssets
            case .photoKitUnavailable, .assetCountMismatch:
                return .libraryAssetUnavailable
            case .cancelled:
                return .exportCancelled
            default:
                return .exportFailed
            }
        }
        if let mediaError = error as? MediaExporterError,
           case .unsupportedOutputType = mediaError {
            return .exportUnsupported
        }
        if error is CancellationError {
            return .exportCancelled
        }
        return .exportFailed
    }

    /// 判別できた失敗理由を、利用者が次の行動を選べる文面へ変換する。
    /// 分類できない場合も、端末が返した有用な説明だけは末尾に残す。
    static func exportFailureDetail(from error: Error) -> String {
        let failure = exportFailure(from: error)

        if failure == .storageUnavailable {
            return L10n.text("書き出し用の空き容量が不足しています。結合中は完成動画とは別に作業用ファイルも作るため、完成サイズより多めの空き容量が必要です。不要な写真や動画を整理して、もう一度お試しください。")
        }

        if let exporterError = error as? DayVideoExporterError {
            switch exporterError {
            case .noAssets:
                return L10n.text("結合対象の動画を1本も確認できませんでした。写真へのアクセス範囲と、アプリの動画が写真アプリに残っているか確認してください。")
            case .assetCountMismatch(let expected, let actual):
                let missing = max(expected - actual, 0)
                return L10n.text("結合予定%d本のうち%d本だけ取得できました（不足%d本）。写真へのアクセス範囲、削除済みの動画、iCloudから未取得の動画を確認してください。", expected, actual, missing)
            case .missingVideoTrack:
                return L10n.text("動画データを読み込めない素材が含まれていたため、結合を止めました。写真アプリで各動画を再生できるか確認してください。")
            case .photoKitUnavailable:
                return L10n.text("写真ライブラリまたはiCloudから動画を取得できませんでした。通信状態を確認し、写真アプリで対象動画を一度開いてから、もう一度お試しください。")
            case .cancelled:
                return VlogishFailure.exportCancelled.message
            case .exportFailed(let message):
                return detail(
                    base: VlogishFailure.exportFailed.message,
                    systemMessage: message
                )
            }
        }

        if let mediaError = error as? MediaExporterError {
            switch mediaError {
            case .exportSessionUnavailable:
                return L10n.text("iOSが動画の書き出し処理を開始できませんでした。ほかの動画処理を終了し、アプリを開き直してからお試しください。")
            case .unsupportedOutputType:
                return VlogishFailure.exportUnsupported.message
            case .audioTrackMissing:
                return L10n.text("結合後の動画から音声が失われたため、壊れた動画を共有せず処理を止めました。元の動画を写真アプリで再生できるか確認してください。")
            case .exportFailed(let message):
                return detail(
                    base: VlogishFailure.exportFailed.message,
                    systemMessage: message
                )
            }
        }

        if failure == .libraryAssetUnavailable {
            return L10n.text("iCloudから動画を取得する通信、または写真ライブラリの読み込みに失敗しました。通信状態と写真へのアクセス範囲を確認してください。")
        }

        return detail(
            base: failure.message,
            systemMessage: error.localizedDescription
        )
    }

    static func libraryFailure(from error: Error) -> VlogishFailure {
        if let repositoryError = error as? PhotoLibraryRepositoryError {
            switch repositoryError {
            case .authorizationNotDetermined, .permissionDenied:
                return .photoLibraryReadPermission
            }
        }
        return .libraryAssetUnavailable
    }

    /// 端末の空き容量不足か。書き出しの再挑戦を止める判断にも使う。
    static func isStorageUnavailable(_ error: Error) -> Bool {
        errorChain(error).contains { current in
            if current.domain == NSCocoaErrorDomain,
               current.code == NSFileWriteOutOfSpaceError {
                return true
            }
            if current.domain == NSPOSIXErrorDomain, current.code == 28 {
                return true
            }
            if current.domain == AVFoundationErrorDomain,
               current.code == AVError.Code.diskFull.rawValue {
                return true
            }
            return false
        }
    }

    private static func isPhotoLibraryUnavailable(_ error: Error) -> Bool {
        errorChain(error).contains { current in
            current.domain == NSURLErrorDomain
                || current.domain == "CKErrorDomain"
                || current.domain == "PHPhotosErrorDomain"
        }
    }

    private static func errorChain(_ error: Error) -> [NSError] {
        var chain: [NSError] = []
        var candidate: NSError? = error as NSError
        var visited: Set<ObjectIdentifier> = []

        while let current = candidate {
            let identifier = ObjectIdentifier(current)
            guard visited.insert(identifier).inserted else { break }
            chain.append(current)
            candidate = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return chain
    }

    private static func detail(base: String, systemMessage: String) -> String {
        let message = systemMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              message != base,
              !message.localizedCaseInsensitiveContains("operation couldn’t be completed"),
              !message.localizedCaseInsensitiveContains("operation could not be completed") else {
            return base
        }
        return L10n.text("%@\n原因: %@", base, message)
    }
}
