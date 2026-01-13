import AVFoundation
import Foundation

class AudioRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    
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
        audioRecorder?.record()
    }
    
    @discardableResult
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        let url = recordingURL
        audioRecorder = nil
        return url
    }
    
    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
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

