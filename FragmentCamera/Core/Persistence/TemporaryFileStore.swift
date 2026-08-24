import Foundation

enum TemporaryFileStoreError: LocalizedError {
    case directoryUnavailable

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable:
            return L10n.text("一時保存領域を準備できませんでした。端末の空き容量を確認してください。")
        }
    }
}

/// 撮影・変換・共有で使う一時ファイルの生成と破棄を一元管理する。
/// daylog 専用ディレクトリだけを対象にするため、他機能の一時ファイルを誤って消さない。
final class TemporaryFileStore {
    private let fileManager: FileManager
    private let rootURL: URL
    private let now: () -> Date

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL
            ?? fileManager.temporaryDirectory.appendingPathComponent("daylog", isDirectory: true)
        self.now = now

        try? prepareDirectory()
        removeFilesOlderThan(24 * 60 * 60)
    }

    func makeURL(prefix: String, pathExtension: String) throws -> URL {
        try prepareDirectory()
        let safePrefix = sanitized(prefix, fallback: "video")
        let safeExtension = sanitized(pathExtension, fallback: "mp4")
        return rootURL
            .appendingPathComponent("\(safePrefix)-\(UUID().uuidString)")
            .appendingPathExtension(safeExtension)
    }

    func removeIfExists(at url: URL) {
        guard isManagedURL(url) else {
            AppLog.storage.warning(
                "temp.remove.refused file=\(url.lastPathComponent, privacy: .private(mask: .hash))"
            )
            return
        }
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            AppLog.storage.warning(
                "temp.remove.fail file=\(url.lastPathComponent, privacy: .private(mask: .hash)) reason=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    func manages(_ url: URL) -> Bool {
        isManagedURL(url)
    }

    func removeFilesOlderThan(_ age: TimeInterval) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = now().addingTimeInterval(-age)
        for url in urls {
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ),
            values.isRegularFile == true,
            let modificationDate = values.contentModificationDate,
            modificationDate < cutoff else { continue }
            removeIfExists(at: url)
        }
    }

    private func prepareDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            AppLog.storage.error(
                "temp.directory.fail reason=\(error.localizedDescription, privacy: .private)"
            )
            throw TemporaryFileStoreError.directoryUnavailable
        }
    }

    private func sanitized(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(scalars))
        return result.isEmpty ? fallback : result
    }

    private func isManagedURL(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(rootPath)
    }
}
