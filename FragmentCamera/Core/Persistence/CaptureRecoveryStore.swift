import Foundation

struct RecoverableCapture: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let capturedAt: Date
}

enum CaptureRecoveryStoreError: LocalizedError {
    case directoryUnavailable
    case sourceMissing

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable:
            return L10n.text("未保存動画の復旧領域を準備できませんでした。")
        case .sourceMissing:
            return L10n.text("復旧する録画ファイルが見つかりませんでした。")
        }
    }
}

/// 写真ライブラリへの保存が完了するまで、撮影原本を永続領域に保持する。
///
/// 一時領域とは分離しているため、アプリが保存処理中に終了しても次回起動時に
/// 原本を検知できる。自動で写真ライブラリへ再保存せず、共有または明示削除を
/// ユーザーに委ねることで、完了直前の終了による二重保存も避ける。
final class CaptureRecoveryStore {
    private static let filenamePrefix = "unsaved-"
    private let fileManager: FileManager
    private let rootURL: URL

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.rootURL = applicationSupport
                .appendingPathComponent("daylog", isDirectory: true)
                .appendingPathComponent("CaptureRecovery", isDirectory: true)
        }
        try? prepareDirectory()
    }

    func stageCapture(at sourceURL: URL, capturedAt: Date) throws -> RecoverableCapture {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CaptureRecoveryStoreError.sourceMissing
        }
        try prepareDirectory()

        let identifier = UUID().uuidString
        let pathExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destinationURL = rootURL
            .appendingPathComponent("\(Self.filenamePrefix)\(identifier)")
            .appendingPathExtension(pathExtension)
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        try fileManager.setAttributes(
            [.creationDate: capturedAt, .modificationDate: capturedAt],
            ofItemAtPath: destinationURL.path
        )
        return RecoverableCapture(
            id: identifier,
            url: destinationURL,
            capturedAt: capturedAt
        )
    }

    func recoverableCaptures() -> [RecoverableCapture] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isRegularFileKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard url.lastPathComponent.hasPrefix(Self.filenamePrefix),
                  let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                  ),
                  values.isRegularFile == true else {
                return nil
            }
            let identifier = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: Self.filenamePrefix, with: "")
            return RecoverableCapture(
                id: identifier,
                url: url,
                capturedAt: values.contentModificationDate ?? .distantPast
            )
        }
        .sorted { lhs, rhs in
            if lhs.capturedAt == rhs.capturedAt {
                return lhs.id > rhs.id
            }
            return lhs.capturedAt > rhs.capturedAt
        }
    }

    func discard(_ capture: RecoverableCapture) {
        guard isManagedURL(capture.url),
              fileManager.fileExists(atPath: capture.url.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: capture.url)
        } catch {
            AppLog.storage.warning(
                "recovery.remove.fail file=\(capture.url.lastPathComponent, privacy: .private(mask: .hash)) reason=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private func prepareDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            var directoryURL = rootURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directoryURL.setResourceValues(values)
        } catch {
            AppLog.storage.error(
                "recovery.directory.fail reason=\(error.localizedDescription, privacy: .private)"
            )
            throw CaptureRecoveryStoreError.directoryUnavailable
        }
    }

    private func isManagedURL(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(rootPath)
    }
}
