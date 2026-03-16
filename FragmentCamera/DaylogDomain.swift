import Foundation
import Photos
import UIKit

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
}

enum CapturePermissionState: Equatable {
    case unknown
    case granted
    case denied
}

enum SessionState: Equatable {
    case preparing
    case ready
    case interrupted
    case blocked(CaptureReadinessReason)
}

enum CaptureSavePhase: String, Equatable, Sendable {
    case idle
    case recorded
    case processing
    case saved
    case indexed
}

enum RecordingState: Equatable {
    case idle
    case recording(progress: Double, remaining: TimeInterval)
    case saving(CaptureSavePhase)
}

enum CameraPosition: String, Equatable {
    case front
    case back
}

struct CaptureState: Equatable {
    var permission: CapturePermissionState = .unknown
    var session: SessionState = .preparing
    var recording: RecordingState = .idle
    var selectedDuration: TimeInterval = 3
    var torchEnabled: Bool = false
    var cameraPosition: CameraPosition = .back
    var isTorchAvailable: Bool = false
}

enum LibraryChangeEvent: Sendable {
    case photoLibraryDidChange
}

struct ProcessedVideoResult: Sendable {
    let finalURL: URL
    let stampApplied: Bool
    let didFallback: Bool
}

struct IdentifiableAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

struct IdentifiableAssets: Identifiable {
    let assets: [PHAsset]
    var id: String { assets.map(\.localIdentifier).joined(separator: ",") }
}

enum PlaybackRoute: Identifiable {
    case single(IdentifiableAsset)
    case day(IdentifiableAssets)

    var id: String {
        switch self {
        case .single(let asset):
            return "single:\(asset.id)"
        case .day(let assets):
            return "day:\(assets.id)"
        }
    }
}

enum DaylogFormatters {
    static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "E"
        return formatter
    }()

    static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: Calendar.current.startOfDay(for: date))
    }

    static func durationLabel(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
