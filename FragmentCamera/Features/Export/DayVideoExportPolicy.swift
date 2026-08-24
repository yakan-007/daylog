import Foundation
import CoreGraphics

enum DayVideoExportLoad: Equatable {
    case standard
    case elevated
    case heavy
}

struct DayVideoExportAssessment: Equatable {
    let load: DayVideoExportLoad
    let clipCount: Int
    let totalDuration: TimeInterval

    var requiresConfirmation: Bool {
        load != .standard
    }

    var indicatorText: String? {
        switch load {
        case .standard:
            return nil
        case .elevated:
            return L10n.text("%d本・結合注意", clipCount)
        case .heavy:
            return L10n.text("%d本・分割処理", clipCount)
        }
    }

    var confirmationTitle: String {
        switch load {
        case .standard:
            return L10n.text("動画を結合しますか？")
        case .elevated:
            return L10n.text("本数の多い日です")
        case .heavy:
            return L10n.text("本数の多い日です")
        }
    }

    var confirmationMessage: String {
        switch load {
        case .standard:
            return ""
        case .elevated:
            return L10n.text("結合する本数に上限はありません。この日は%d本あります。時間と一時容量が増えるため、充電しながらアプリを開いたまま結合してください。", clipCount)
        case .heavy:
            return L10n.text("結合する本数に上限はありません。この日は%d本あります。安定性を優先して%d本ずつ分割処理します。完了まで充電しながらアプリを開いたままにしてください。", clipCount, DayVideoExportPolicy.chunkSize)
        }
    }
}

enum DayVideoExportPolicy {
    /// 本数が多い日は確認を出し、80本以上で巨大なCompositionを作らない。
    static let cautionClipCount = 60
    static let heavyClipCount = 80

    /// 1つのAVMutableCompositionが同時に参照する素材数を抑える。
    static let chunkSize = 24

    static var guidanceText: String {
        L10n.text("結合する本数に上限はありません。%d本以上では事前に確認し、%d本以上は%d本ずつ分割して処理します。", cautionClipCount, heavyClipCount, chunkSize)
    }

    static func orderedIndices(
        creationDates: [Date?],
        identifiers: [String]
    ) -> [Int] {
        precondition(creationDates.count == identifiers.count)
        return creationDates.indices.sorted { left, right in
            let leftDate = creationDates[left] ?? .distantPast
            let rightDate = creationDates[right] ?? .distantPast
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            if identifiers[left] != identifiers[right] {
                return identifiers[left] < identifiers[right]
            }
            return left < right
        }
    }

    static func hasCompleteAssetSet(expected: Int, actual: Int) -> Bool {
        expected > 0 && expected == actual
    }

    /// 縦横素材が混在しても正方形動画にしない。総再生時間が長い向きを採用し、
    /// 同率なら一日の最初のクリップの向きを維持する。
    static func preferredCanvasSourceSize(
        sizes: [CGSize],
        durations: [TimeInterval]
    ) -> CGSize {
        precondition(sizes.count == durations.count)
        guard let firstSize = sizes.first else { return .zero }

        let landscapeDuration = zip(sizes, durations).reduce(0.0) { total, item in
            item.0.width >= item.0.height ? total + max(item.1, 0) : total
        }
        let portraitDuration = zip(sizes, durations).reduce(0.0) { total, item in
            item.0.height > item.0.width ? total + max(item.1, 0) : total
        }
        let prefersLandscape: Bool
        if landscapeDuration == portraitDuration {
            prefersLandscape = firstSize.width >= firstSize.height
        } else {
            prefersLandscape = landscapeDuration > portraitDuration
        }

        let matchingSizes = sizes.filter {
            ($0.width >= $0.height) == prefersLandscape
        }
        return matchingSizes.max {
            ($0.width * $0.height) < ($1.width * $1.height)
        } ?? firstSize
    }

    static func chunkRanges(for clipCount: Int) -> [Range<Int>] {
        guard clipCount > 0 else { return [] }
        return stride(from: 0, to: clipCount, by: chunkSize).map { start in
            start..<min(start + chunkSize, clipCount)
        }
    }

    static func assess(
        clipCount: Int,
        totalDuration: TimeInterval
    ) -> DayVideoExportAssessment {
        let load: DayVideoExportLoad
        if clipCount >= heavyClipCount {
            load = .heavy
        } else if clipCount >= cautionClipCount {
            load = .elevated
        } else {
            load = .standard
        }
        return DayVideoExportAssessment(
            load: load,
            clipCount: clipCount,
            totalDuration: totalDuration
        )
    }
}

struct DayVideoExportConfirmation: Identifiable, Equatable {
    let dayID: String
    let assessment: DayVideoExportAssessment

    var id: String { dayID }
}
