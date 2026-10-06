import Foundation

enum ThumbnailState: String, Codable, Sendable {
    case placeholder
    case photoKit
}

struct ClipSummary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let assetLocalIdentifier: String
    let capturedAt: Date
    let dayKey: String
    let duration: TimeInterval
    let thumbnailState: ThumbnailState

    init(
        assetLocalIdentifier: String,
        capturedAt: Date,
        dayKey: String,
        duration: TimeInterval,
        thumbnailState: ThumbnailState = .photoKit
    ) {
        self.id = assetLocalIdentifier
        self.assetLocalIdentifier = assetLocalIdentifier
        self.capturedAt = capturedAt
        self.dayKey = dayKey
        self.duration = duration
        self.thumbnailState = thumbnailState
    }
}

struct DaySection: Identifiable, Hashable, Sendable {
    let dayKey: String
    let date: Date
    let clipCount: Int
    let totalDuration: TimeInterval
    let clips: [ClipSummary]

    var id: String { dayKey }

    var chronologicalClips: [ClipSummary] {
        clips.sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt {
                return lhs.capturedAt < rhs.capturedAt
            }
            return lhs.assetLocalIdentifier < rhs.assetLocalIdentifier
        }
    }
}

struct DayCalendarSummary: Identifiable, Hashable, Sendable {
    let dayKey: String
    let date: Date
    let clipCount: Int
    let totalDuration: TimeInterval
    let previewAssetIdentifier: String
    /// その日の0時からの経過秒。カレンダーで「いつ撮ったか」を描くために使う。
    var clipDayOffsets: [TimeInterval] = []

    var id: String { dayKey }
}

enum CameraSessionState: Equatable, Sendable {
    case preparing
    case ready
    case interrupted
    case blocked
    case unavailable
}

enum CaptureSavePhase: String, Equatable, Sendable {
    case idle
    case recorded
    case processing
    case saved
    case indexed
}

struct CameraPermissionIssue: Equatable, Sendable {
    let title: String
    let message: String
}

enum CaptureDurationPolicy {
    static let options: [TimeInterval] = [1, 2, 3, 4, 5]
    static let defaultValue: TimeInterval = 3

    static func normalized(_ duration: TimeInterval?) -> TimeInterval {
        guard let duration, options.contains(duration) else { return defaultValue }
        return duration
    }
}

enum VideoStorageMode: String, CaseIterable, Codable, Sendable {
    case standard
    case compact

    static func normalized(_ rawValue: String) -> VideoStorageMode {
        VideoStorageMode(rawValue: rawValue) ?? .standard
    }

    var title: String {
        switch self {
        case .standard:
            return L10n.text("標準")
        case .compact:
            return L10n.text("節約")
        }
    }

}

/// 撮影の向き。Vlogish は縦だけで撮る（1日分をつないだ時に向きが混ざらないように）。
///
/// 横撮影を戻す時は、case を足し、`CaptureRotationPolicy` の候補角度と
/// `VlogishAppDelegate.supportedInterfaceOrientations` を対応させ、設定に選択肢を足す。
enum CaptureOrientationMode: String, Codable, Sendable {
    case portrait

    static let current: CaptureOrientationMode = .portrait
}

struct CameraEngineState: Equatable, Sendable {
    var session: CameraSessionState = .preparing
    var isRecording: Bool = false
    var isTorchAvailable: Bool = false
    var savePhase: CaptureSavePhase = .idle
    var lastSavedAssetLocalIdentifier: String?
    var saveFailure: VlogishFailure?
    var recoverableCapture: RecoverableCapture?
    var permissionIssue: CameraPermissionIssue?
    var isPermissionAlertPresented: Bool = false
}

enum LibraryChangeEvent: Sendable {
    case photoLibraryDidChange
}

struct ProcessedVideoResult: Sendable {
    let finalURL: URL
    let stampApplied: Bool
    let didFallback: Bool
}

struct SavedRecordingResult: Sendable {
    let identifier: String
    let stampApplied: Bool
    let didFallback: Bool
}
