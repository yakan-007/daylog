import Foundation

struct CaptureReadinessPolicy: Equatable {
    var minimumFrameCount = 3
    var minimumStableFrameCount = 2
    var timeout: TimeInterval = 1
    var minimumFrameCountForTimeout = 2
}

enum CaptureReadinessDecision: Equatable {
    case waiting
    case ready
    case timedOut
}

final class CaptureReadinessMonitor {
    private let policy: CaptureReadinessPolicy
    private let lock = NSLock()
    private var frameCount = 0
    private var stableFrameCount = 0
    private var resetAt: Date

    init(
        policy: CaptureReadinessPolicy = CaptureReadinessPolicy(),
        now: Date = Date()
    ) {
        self.policy = policy
        self.resetAt = now
    }

    func reset(at now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        frameCount = 0
        stableFrameCount = 0
        resetAt = now
    }

    func observeFrame(isDeviceAdjusting: Bool, at now: Date = Date()) -> CaptureReadinessDecision {
        lock.lock()
        defer { lock.unlock() }

        frameCount += 1
        stableFrameCount = isDeviceAdjusting ? 0 : stableFrameCount + 1

        if frameCount >= policy.minimumFrameCount,
           stableFrameCount >= policy.minimumStableFrameCount {
            return .ready
        }

        if frameCount >= policy.minimumFrameCountForTimeout,
           now.timeIntervalSince(resetAt) >= policy.timeout {
            return .timedOut
        }

        return .waiting
    }
}
