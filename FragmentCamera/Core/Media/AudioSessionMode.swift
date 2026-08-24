import AVFAudio

enum AudioSessionMode {
    static func activateCapture() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setMode(.videoRecording)
            try session.setActive(true)
        } catch {
            AppLog.capture.error("Failed to activate capture audio session: \(error.localizedDescription)")
        }
    }

    static func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        if configurePlayback(session: session, mode: .moviePlayback) {
            return
        }

        if configurePlayback(session: session, mode: .default) {
            AppLog.capture.info("Playback audio session activated with default mode fallback")
            return
        }

        AppLog.capture.error("Failed to activate playback audio session after fallback attempts")
    }

    @discardableResult
    private static func configurePlayback(
        session: AVAudioSession,
        mode: AVAudioSession.Mode
    ) -> Bool {
        do {
            try session.setCategory(.playback)
            try session.setMode(mode)
            try session.setActive(true)
            return true
        } catch {
            AppLog.capture.error("Failed to activate playback audio session (mode=\(mode.rawValue, privacy: .public)): \(error.localizedDescription)")
            return false
        }
    }
}
