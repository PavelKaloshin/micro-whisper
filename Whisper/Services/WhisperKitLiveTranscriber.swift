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

    /// Loading a WhisperKit model takes a few seconds, so cache it across live
    /// sessions — the first start pays the cost, later starts are instant.
    @MainActor private static var cachedPipe: WhisperKit?
    @MainActor private static var cachedModel: String?

    /// Whether the model for `model` is already loaded (so the UI can skip the
    /// "loading model" indicator).
    static func isModelCached(_ model: String) -> Bool {
        cachedPipe != nil && cachedModel == model
    }

    /// Preload the model in the background so the first live session is instant.
    static func prewarm(model: String = "base") {
        guard !isModelCached(model) else { return }
        Task { @MainActor in
            if let pipe = try? await WhisperKit(model: model, verbose: false, load: true) {
                cachedPipe = pipe
                cachedModel = model
            }
        }
    }

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
        if let cached = Self.cachedPipe, Self.cachedModel == modelName {
            pipe = cached
        } else {
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
            Self.cachedPipe = pipe
            Self.cachedModel = modelName
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
            let raw = joined.isEmpty ? newState.currentText : joined
            let text = Self.cleanTranscript(raw)
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

    /// Strip Whisper special tokens / placeholders that should never reach the UI
    /// or the pasted text: `<|startoftranscript|>`, `<|ru|>`, `<|0.00|>`, etc., the
    /// `[BLANK_AUDIO]` marker, and WhisperKit's "Waiting for speech..." placeholder.
    nonisolated static func cleanTranscript(_ text: String) -> String {
        var t = text.replacingOccurrences(
            of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
        t = t.replacingOccurrences(of: "Waiting for speech...", with: "")
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stop() async -> String {
        await transcriber?.stopStreamTranscription()
        streamTask?.cancel()
        streamTask = nil
        transcriber = nil
        return latestText
    }
}
