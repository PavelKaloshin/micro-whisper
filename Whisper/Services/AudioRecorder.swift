import AVFoundation
import Foundation
import Combine

class AudioRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var levelTimer: Timer?
    
    // Published audio level for UI updates
    let audioLevelPublisher = PassthroughSubject<Float, Never>()
    
    override init() {
        super.init()
    }
    
    func startRecording() throws {
        // Request microphone permission
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch permission {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw RecordingError.permissionNotGranted
        case .denied, .restricted:
            throw RecordingError.permissionDenied
        case .authorized:
            break
        @unknown default:
            break
        }
        
        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "whisper_recording_\(UUID().uuidString).m4a"
        recordingURL = tempDir.appendingPathComponent(fileName)
        
        guard let url = recordingURL else {
            throw RecordingError.failedToCreateFile
        }
        
        // Configure audio settings optimized for Whisper
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,  // 16kHz is optimal for Whisper
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true  // Enable metering for audio levels
        audioRecorder?.record()
        
        // Start level monitoring
        startLevelMonitoring()
    }
    
    @discardableResult
    func stopRecording() -> URL? {
        stopLevelMonitoring()
        audioRecorder?.stop()
        let url = recordingURL
        audioRecorder = nil
        return url
    }
    
    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }
    
    // MARK: - Audio Level Monitoring
    
    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateAudioLevel()
        }
    }
    
    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
    
    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        
        recorder.updateMeters()
        
        // Get average power in decibels (-160 to 0)
        let averagePower = recorder.averagePower(forChannel: 0)
        
        // Normalize to 0-1 range
        // -50 dB is roughly silence, 0 dB is max
        let minDb: Float = -50
        let normalizedLevel = max(0, min(1, (averagePower - minDb) / (-minDb)))
        
        audioLevelPublisher.send(normalizedLevel)
    }
}

// MARK: - AVAudioRecorderDelegate
extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished unsuccessfully")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Recording encode error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors
enum RecordingError: LocalizedError {
    case permissionNotGranted
    case permissionDenied
    case failedToCreateFile
    case recordingFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionNotGranted:
            return "Microphone permission not yet granted. Please try again."
        case .permissionDenied:
            return "Microphone access denied. Please enable in System Settings > Privacy & Security > Microphone."
        case .failedToCreateFile:
            return "Failed to create recording file."
        case .recordingFailed:
            return "Recording failed."
        }
    }
}

