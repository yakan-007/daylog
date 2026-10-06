import Foundation

enum VlogClipEditStoreError: LocalizedError {
    case unsupportedVersion(Int)
    case unreadableData(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return L10n.text("編集データの形式（%d）には対応していません。", version)
        case .unreadableData:
            return L10n.text("編集データを読み込めませんでした。")
        }
    }
}

/// Vlogishの非破壊編集を原本とは別に永続化する。
///
/// 読めないファイル（壊れている・形式が合わない）は上書きせず、別名で退避してから空で始める。
/// 編集機能そのものが使えなくなることを避けつつ、元のデータは失わない。
actor VlogClipEditStore {
    private struct Document: Codable {
        /// 編集データの形（VlogClipEdit）と必ず一緒に上げる。
        static var currentVersion: Int { VlogClipEdit.currentVersion }

        let version: Int
        let edits: [VlogClipEdit]
    }

    private struct DocumentHeader: Decodable {
        let version: Int
    }

    private let fileURL: URL
    private var editsByIdentifier: [String: VlogClipEdit] = [:]
    private var hasLoaded = false
    private var loadFailure: Error?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func edit(for assetLocalIdentifier: String) throws -> VlogClipEdit? {
        try loadIfNeeded()
        return editsByIdentifier[assetLocalIdentifier]
    }

    func edits(for assetLocalIdentifiers: [String]) throws -> [VlogClipEdit?] {
        try loadIfNeeded()
        return assetLocalIdentifiers.map { editsByIdentifier[$0] }
    }

    func save(_ edit: VlogClipEdit, clipDuration: TimeInterval) throws {
        try loadIfNeeded()
        let normalized = edit.normalized(for: clipDuration)
        var updated = editsByIdentifier
        updated[normalized.assetLocalIdentifier] = normalized
        try persist(updated)
        editsByIdentifier = updated
    }

    func removeEdit(for assetLocalIdentifier: String) throws {
        try loadIfNeeded()
        guard editsByIdentifier[assetLocalIdentifier] != nil else {
            return
        }
        var updated = editsByIdentifier
        updated.removeValue(forKey: assetLocalIdentifier)
        try persist(updated)
        editsByIdentifier = updated
    }

    private func loadIfNeeded() throws {
        if let loadFailure { throw loadFailure }
        guard !hasLoaded else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            hasLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            // リリース前の方針: 形式が古い編集データは読まずに破棄し、新しい形式で作り直す。
            let header = try JSONDecoder().decode(DocumentHeader.self, from: data)
            guard header.version == Document.currentVersion else {
                AppLog.save.notice(
                    "vlog_edit.load.discard_outdated version=\(header.version, privacy: .public)"
                )
                editsByIdentifier = [:]
                hasLoaded = true
                return
            }
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == Document.currentVersion else {
                throw VlogClipEditStoreError.unsupportedVersion(document.version)
            }
            if let unsupportedEdit = document.edits.first(where: {
                $0.version != VlogClipEdit.currentVersion
            }) {
                throw VlogClipEditStoreError.unsupportedVersion(unsupportedEdit.version)
            }
            editsByIdentifier = Dictionary(
                document.edits.map { ($0.assetLocalIdentifier, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            hasLoaded = true
        } catch {
            AppLog.save.error(
                "vlog_edit.load.fail reason=\(error.localizedDescription, privacy: .private)"
            )
            // 読めないファイルは退避して、空の状態から使えるようにする。
            if moveUnreadableFileAside() {
                editsByIdentifier = [:]
                hasLoaded = true
                return
            }
            // 退避もできない時だけ、上書き事故を防ぐために以後の保存を止める。
            let failure: Error
            if error is VlogClipEditStoreError {
                failure = error
            } else {
                failure = VlogClipEditStoreError.unreadableData(error)
            }
            loadFailure = failure
            throw failure
        }
    }

    /// 読めなかったファイルを `clip-edits.unreadable-<時刻>.json` へ移す。成功したら true。
    private func moveUnreadableFileAside() -> Bool {
        let stamp = Int(Date().timeIntervalSince1970)
        let backupURL = fileURL.deletingPathExtension()
            .appendingPathExtension("unreadable-\(stamp)")
            .appendingPathExtension("json")
        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            AppLog.save.notice("vlog_edit.load.moved_aside")
            return true
        } catch {
            AppLog.save.error(
                "vlog_edit.load.move_aside.fail reason=\(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    private func persist(_ editsByIdentifier: [String: VlogClipEdit]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let ordered = editsByIdentifier.values.sorted {
            $0.assetLocalIdentifier < $1.assetLocalIdentifier
        }
        let document = Document(version: Document.currentVersion, edits: ordered)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("vlogish", isDirectory: true)
            .appendingPathComponent("clip-edits.json")
    }
}
