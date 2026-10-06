import Foundation

actor ClipMetadataStore {
    private let fileURL: URL
    private var clipsByID: [String: ClipSummary] = [:]

    init(filename: String = "vlogish-clip-metadata.json") {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryURL = baseURL.appendingPathComponent("vlogish", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.fileURL = directoryURL.appendingPathComponent(filename)
        self.clipsByID = Self.load(from: fileURL)
    }

    func replaceAll(with clips: [ClipSummary]) {
        // PhotoKit側で同じIDが重複して返っても落ちないよう、後勝ちでまとめる。
        clipsByID = Dictionary(clips.map { ($0.assetLocalIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })
        persist()
    }

    func upsert(_ clip: ClipSummary) {
        clipsByID[clip.assetLocalIdentifier] = clip
        persist()
    }

    func fetchDaySections(limit: Int = 30, cursor: String? = nil) -> [DaySection] {
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
            return makeDaySection(dayKey: key, clips: clips)
        }
    }

    func fetchCalendarSummaries() -> [DayCalendarSummary] {
        let grouped = Dictionary(grouping: clipsByID.values) { $0.dayKey }
        return grouped.keys.sorted(by: >).compactMap { key in
            guard let clips = grouped[key],
                  let section = makeDaySection(dayKey: key, clips: clips),
                  let previewAssetIdentifier = section.clips.first?.assetLocalIdentifier else {
                return nil
            }
            let calendar = Calendar.current
            let offsets = section.clips.map { clip in
                clip.capturedAt.timeIntervalSince(calendar.startOfDay(for: clip.capturedAt))
            }
            return DayCalendarSummary(
                dayKey: key,
                date: section.date,
                clipCount: section.clipCount,
                totalDuration: section.totalDuration,
                previewAssetIdentifier: previewAssetIdentifier,
                clipDayOffsets: offsets.sorted()
            )
        }
    }

    func fetchDaySection(dayKey: String) -> DaySection? {
        let clips = clipsByID.values.filter { $0.dayKey == dayKey }
        return makeDaySection(dayKey: dayKey, clips: clips)
    }

    private func makeDaySection(
        dayKey: String,
        clips: some Sequence<ClipSummary>
    ) -> DaySection? {
        let sortedClips = clips.sorted(by: { $0.capturedAt > $1.capturedAt })
        guard let first = sortedClips.first else { return nil }
        return DaySection(
            dayKey: dayKey,
            date: Calendar.current.startOfDay(for: first.capturedAt),
            clipCount: sortedClips.count,
            totalDuration: sortedClips.reduce(0) { $0 + $1.duration },
            clips: sortedClips
        )
    }

    private func persist() {
        let clips = clipsByID.values.sorted(by: { $0.capturedAt > $1.capturedAt })
        do {
            let data = try JSONEncoder().encode(clips)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            AppLog.export.error("metadata.persist.fail reason=\(error.localizedDescription, privacy: .private)")
        }
    }

    private static func load(from url: URL) -> [String: ClipSummary] {
        guard let data = try? Data(contentsOf: url),
              let clips = try? JSONDecoder().decode([ClipSummary].self, from: data) else {
            return [:]
        }
        return Dictionary(clips.map { ($0.assetLocalIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })
    }
}
