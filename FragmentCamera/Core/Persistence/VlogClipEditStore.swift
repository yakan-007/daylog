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
/// 読込に失敗した場合は空データとして扱わず、以後の保存も失敗させる。
/// 壊れたファイルを無意識に上書きしないための挙動。
actor VlogClipEditStore {
    private struct Document: Codable {
        static let currentVersion = 1

        let version: Int
        let edits: [VlogClipEdit]
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
            let failure: Error
            if error is VlogClipEditStoreError {
                failure = error
            } else {
                failure = VlogClipEditStoreError.unreadableData(error)
            }
            loadFailure = failure
            AppLog.save.error(
                "vlog_edit.load.fail reason=\(error.localizedDescription, privacy: .private)"
            )
            throw failure
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
