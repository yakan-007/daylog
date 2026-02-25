import AVFAudio

enum AudioSessionMode {
    static func activateCapture() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Recording + playback on speaker for camera workflow.
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setMode(.videoRecording)
            try session.setActive(true)
        } catch {
            AppLog.capture.error("Failed to activate capture audio session: \(error.localizedDescription)")
        }
    }

    static func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Ensure video playback audio is audible even if capture session configured earlier.
            try session.setCategory(.playback, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setMode(.moviePlayback)
            try session.setActive(true)
        } catch {
            AppLog.capture.error("Failed to activate playback audio session: \(error.localizedDescription)")
        }
    }
}
