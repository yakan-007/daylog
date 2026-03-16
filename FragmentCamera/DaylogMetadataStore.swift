import Foundation

actor ClipMetadataStore {
    private let fileURL: URL
    private var clipsByID: [String: ClipSummary] = [:]

    init(filename: String = "daylog-clip-metadata.json") {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryURL = baseURL.appendingPathComponent("daylog", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.fileURL = directoryURL.appendingPathComponent(filename)
        self.clipsByID = Self.load(from: fileURL)
    }

    func upsert(clips: [ClipSummary]) async {
        for clip in clips {
            clipsByID[clip.assetLocalIdentifier] = clip
        }
        persist()
    }

    func delete(assetLocalIdentifiers: [String]) async {
        for identifier in assetLocalIdentifiers {
            clipsByID.removeValue(forKey: identifier)
        }
        persist()
    }

    func replaceAll(with clips: [ClipSummary]) async {
        clipsByID = Dictionary(uniqueKeysWithValues: clips.map { ($0.assetLocalIdentifier, $0) })
        persist()
    }

    func fetchDaySections(limit: Int = 30, cursor: String? = nil) async -> [DaySection] {
        let grouped = Dictionary(grouping: clipsByID.values) { $0.dayKey }
        let sortedKeys = grouped.keys.sorted(by: >)
        let startIndex: Int
        if let cursor, let index = sortedKeys.firstIndex(of: cursor) {
            startIndex = sortedKeys.index(after: index)
        } else {
            startIndex = 0
        }

        let pageKeys = Array(sortedKeys.dropFirst(startIndex).prefix(limit))
        return pageKeys.compactMap { key in
            guard let clips = grouped[key] else { return nil }
            let sortedClips = clips.sorted(by: { $0.capturedAt > $1.capturedAt })
            guard let first = sortedClips.first else { return nil }
            return DaySection(
                dayKey: key,
                date: Calendar.current.startOfDay(for: first.capturedAt),
                clipCount: sortedClips.count,
                totalDuration: sortedClips.reduce(0) { $0 + $1.duration },
                clips: sortedClips
            )
        }
    }

    func latestClip() async -> ClipSummary? {
        clipsByID.values.max(by: { $0.capturedAt < $1.capturedAt })
    }

    private func persist() {
        let clips = clipsByID.values.sorted(by: { $0.capturedAt > $1.capturedAt })
        do {
            let data = try JSONEncoder().encode(clips)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            AppLog.export.error("metadata.persist.fail reason=\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [String: ClipSummary] {
        guard let data = try? Data(contentsOf: url),
              let clips = try? JSONDecoder().decode([ClipSummary].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: clips.map { ($0.assetLocalIdentifier, $0) })
    }
}
