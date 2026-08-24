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

enum CaptureOrientationMode: String, CaseIterable, Codable, Sendable {
    case portrait
    case landscape

    static func normalized(_ rawValue: String) -> CaptureOrientationMode {
        CaptureOrientationMode(rawValue: rawValue) ?? .portrait
    }

    var title: String {
        switch self {
        case .portrait:
            return L10n.text("縦")
        case .landscape:
            return L10n.text("横")
        }
    }
}

struct CameraEngineState: Equatable, Sendable {
    var session: CameraSessionState = .preparing
    var isRecording: Bool = false
    var isTorchAvailable: Bool = false
    var savePhase: CaptureSavePhase = .idle
    var lastSavedAssetLocalIdentifier: String?
    var saveFailure: DaylogFailure?
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
