import Foundation

/// A real-time ("live") speech-to-text backend: it captures audio itself and
/// streams partial transcripts via `onPartial` as the user speaks, returning the
/// final transcript from `stop()`.
///
/// Two implementations exist, selected by `LiveTranscriptionEngine`:
/// - `OpenAIRealtimeLiveTranscriber` — cloud, OpenAI Realtime transcription.
/// - `WhisperKitLiveTranscriber` — on-device, WhisperKit (CoreML).
///
/// Each backend owns its own audio capture (WhisperKit's `AudioStreamTranscriber`
/// and the OpenAI WebSocket path both want raw PCM, not the finished `.m4a` file
/// that `AudioRecorder` produces), so the live path is separate from the classic
/// record→upload flow. Callbacks are delivered on the main actor.
@MainActor
protocol LiveTranscriber: AnyObject {
    /// Called with the best-so-far transcript as it streams in (cumulative text).
    var onPartial: ((String) -> Void)? { get set }
    /// Called if the backend fails mid-stream.
    var onError: ((Error) -> Void)? { get set }
    /// Called with a normalized (0...1) input level for a live mic meter, if the
    /// backend captures audio it can measure. Optional — backends may never call it.
    var onAudioLevel: ((Float) -> Void)? { get set }

    /// Begin capturing and streaming. Throws if setup fails (mic permission,
    /// model download, network, missing API key).
    func start() async throws
    /// Stop capturing and return the final transcript.
    func stop() async -> String
}

/// Which live backend to use. Persisted as a setting; toggled in Settings.
enum LiveTranscriptionEngine: String, CaseIterable {
    case cloud   // OpenAI Realtime transcription
    case local   // WhisperKit on-device

    var displayName: String {
        switch self {
        case .cloud: return "Cloud (OpenAI Realtime)"
        case .local: return "Local (WhisperKit)"
        }
    }

    var shortName: String {
        switch self {
        case .cloud: return "Cloud"
        case .local: return "Local"
        }
    }
}

enum LiveTranscriptionError: LocalizedError {
    case noAPIKey
    case microphonePermissionDenied
    case modelUnavailable(String)
    case audioEngineFailed(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Add your OpenAI API key in Settings."
        case .microphonePermissionDenied:
            return "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
        case .modelUnavailable(let message):
            return "Local model unavailable: \(message)"
        case .audioEngineFailed(let message):
            return "Audio engine error: \(message)"
        case .connectionFailed(let message):
            return "Realtime connection failed: \(message)"
        }
    }
}
