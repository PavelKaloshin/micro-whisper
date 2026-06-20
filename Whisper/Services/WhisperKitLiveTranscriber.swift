import Foundation
import WhisperKit

/// On-device live transcription via WhisperKit's `AudioStreamTranscriber`, which
/// captures the microphone itself and emits confirmed/unconfirmed segments as it
/// runs. The model is downloaded on first use (CoreML). Requires macOS 15+ at
/// runtime for the WhisperKit pipeline.
@MainActor
final class WhisperKitLiveTranscriber: LiveTranscriber {
    var onPartial: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    private let modelName: String
    private let language: String?

    private var transcriber: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?
    private var latestText: String = ""

    /// - Parameters:
    ///   - model: WhisperKit model name (e.g. "base", "small"). "base" balances
    ///            latency and quality for live use across EN/RU.
    ///   - language: ISO-639-1 code, or nil for auto-detect.
    init(model: String = "base", language: String? = nil) {
        self.modelName = model
        self.language = language
    }

    func start() async throws {
        let pipe: WhisperKit
        do {
            // load: true forces loadModels() during init so the tokenizer (and the
            // encoder/decoder) are ready. Without it WhisperKit defers loading and
            // pipe.tokenizer is nil here — the classic record→upload path got away
            // with it because transcribe() loads lazily, but the live path reads
            // tokenizer up front.
            pipe = try await WhisperKit(model: modelName, verbose: false, load: true)
        } catch {
            throw LiveTranscriptionError.modelUnavailable(error.localizedDescription)
        }
        guard let tokenizer = pipe.tokenizer else {
            throw LiveTranscriptionError.modelUnavailable("tokenizer failed to load")
        }

        var options = DecodingOptions()
        options.task = .transcribe
        if let language { options.language = language }

        let transcriber = AudioStreamTranscriber(
            audioEncoder: pipe.audioEncoder,
            featureExtractor: pipe.featureExtractor,
            segmentSeeker: pipe.segmentSeeker,
            textDecoder: pipe.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: pipe.audioProcessor,
            decodingOptions: options
        ) { [weak self] _, newState in
            // Build the best-so-far transcript synchronously, then hand the
            // plain String to the main actor (avoids sending non-Sendable state).
            let segments = newState.confirmedSegments + newState.unconfirmedSegments
            let joined = segments.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let text = joined.isEmpty ? newState.currentText : joined
            // Drive the live meter from WhisperKit's per-buffer relative energy.
            let level = min(1, (newState.bufferEnergy.last ?? 0) * 3)
            Task { @MainActor in
                guard let self else { return }
                self.latestText = text
                self.onPartial?(text)
                self.onAudioLevel?(level)
            }
        }
        self.transcriber = transcriber

        streamTask = Task { [weak self] in
            do {
                try await transcriber.startStreamTranscription()
            } catch {
                await MainActor.run { self?.onError?(error) }
            }
        }
    }

    func stop() async -> String {
        await transcriber?.stopStreamTranscription()
        streamTask?.cancel()
        streamTask = nil
        transcriber = nil
        return latestText
    }
}
