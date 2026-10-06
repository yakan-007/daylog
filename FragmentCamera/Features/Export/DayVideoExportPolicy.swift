import Foundation
import CoreGraphics

enum DayVideoExportLoad: Equatable {
    case standard
    case elevated
    case heavy
    /// 1回に書き出せる本数を超えている。
    case overLimit
}

struct DayVideoExportAssessment: Equatable {
    let load: DayVideoExportLoad
    let clipCount: Int
    let totalDuration: TimeInterval

    var requiresConfirmation: Bool {
        load != .standard
    }

    var canExport: Bool {
        load != .overLimit
    }

    var indicatorText: String? {
        switch load {
        case .standard:
            return nil
        case .elevated:
            return L10n.text("%d本・結合注意", clipCount)
        case .heavy:
            return L10n.text("%d本・分割処理", clipCount)
        case .overLimit:
            return L10n.text("%d本・上限超え", clipCount)
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
        case .overLimit:
            return L10n.text("本数が多すぎます")
        }
    }

    var confirmationMessage: String {
        switch load {
        case .standard:
            return ""
        case .elevated:
            return L10n.text("この日は%d本あります。時間と一時容量が増えるため、充電しながらアプリを開いたまま書き出してください。", clipCount)
        case .heavy:
            return L10n.text("この日は%d本あります。安定して処理するため、%d本ずつ分けて書き出します。完了まで充電しながらアプリを開いたままにしてください。", clipCount, DayVideoExportPolicy.chunkSize)
        case .overLimit:
            return L10n.text("1回に書き出せるのは%d本までです。この日は%d本あります。いらないクリップを外してから、もう一度お試しください。", DayVideoExportPolicy.maxClipCount, clipCount)
        }
    }
}

enum DayVideoExportPolicy {
    /// 本数が多い日は確認を出し、80本以上で巨大なCompositionを作らない。
    static let cautionClipCount = 60
    static let heavyClipCount = 80

    /// 1つのAVMutableCompositionが同時に参照する素材数を抑える。
    static let chunkSize = 24

    /// 1回に書き出せる本数。数秒のクリップなら200本で10分前後になり、これを超える日は想定外として止める。
    static let maxClipCount = 200

    /// 書き出しサイズの見積もり（多めに見る）。標準は1080pのH.264最高画質、節約は720pのHEVC。
    static func estimatedOutputBytesPerSecond(for storageMode: VideoStorageMode) -> Double {
        storageMode == .compact ? 500_000 : 2_500_000
    }

    /// 書き出しに要る一時容量の見積もり。分割する日は、分割ファイルと最終ファイルが同時に残る。
    static func estimatedRequiredBytes(
        totalDuration: TimeInterval,
        clipCount: Int,
        storageMode: VideoStorageMode
    ) -> Int64 {
        let output = max(totalDuration, 0) * estimatedOutputBytesPerSecond(for: storageMode)
        let copies: Double = clipCount >= heavyClipCount ? 2 : 1
        return Int64(output * copies) + 200_000_000
    }

    static var guidanceText: String {
        L10n.text("1回に書き出せるのは%d本までです。%d本以上では事前に確認し、%d本以上は%d本ずつ分けて処理します。", maxClipCount, cautionClipCount, heavyClipCount, chunkSize)
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
        if clipCount > maxClipCount {
            load = .overLimit
        } else if clipCount >= heavyClipCount {
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
