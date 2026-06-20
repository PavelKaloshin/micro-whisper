import Foundation
import AVFoundation

/// Cloud live transcription via OpenAI's Realtime transcription API. Captures the
/// microphone with `AVAudioEngine`, converts to 24 kHz mono PCM16, and streams it
/// over a WebSocket (`wss://api.openai.com/v1/realtime?intent=transcription`),
/// receiving incremental `…input_audio_transcription.delta` / `.completed` events.
@MainActor
final class OpenAIRealtimeLiveTranscriber: LiveTranscriber {
    var onPartial: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    private let model: String
    private let language: String?
    private let apiKeyProvider: () -> String?
    /// When set, this is a live *translation* session (gpt-realtime-translate):
    /// the stream returns text already translated into this output language,
    /// using a different endpoint, session shape, and client event names.
    private let translateTo: String?

    private nonisolated var isTranslating: Bool { translateTo != nil }
    /// The translation endpoint namespaces audio events under "session.".
    private nonisolated var appendEventType: String {
        isTranslating ? "session.input_audio_buffer.append" : "input_audio_buffer.append"
    }

    private let engine = AVAudioEngine()
    // Accessed from both the main actor and the audio render thread / send path.
    // We serialize use in practice (set on start, read in the tap/send, cleared on
    // stop), so opt out of actor isolation rather than hop on every audio buffer.
    nonisolated(unsafe) private var converter: AVAudioConverter?
    nonisolated(unsafe) private var webSocket: URLSessionWebSocketTask?

    private var confirmed = ""   // text from .completed events
    private var pending = ""     // current in-progress deltas
    private var isStopping = false  // true once we intentionally tear the socket down
    private var finalContinuation: CheckedContinuation<Void, Never>?  // resumed on the final transcript
    // True once microphone capture started. Guards stop() from touching
    // engine.inputNode for file-driven sessions (startSessionOnly + streamPCMFile),
    // since merely accessing inputNode instantiates it and triggers the mic
    // permission prompt — unwanted when we only stream a fixture.
    private var audioStarted = false

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true
    )!

    /// - Parameters:
    ///   - model: transcription model (default `gpt-realtime-whisper`, the
    ///            current low-latency streaming transcription model).
    ///   - language: ISO-639-1 hint, or nil for auto-detect.
    ///   - translateTo: output language code for live translation
    ///     (gpt-realtime-translate); nil for plain transcription.
    init(model: String = "gpt-realtime-whisper",
         language: String? = nil,
         translateTo: String? = nil,
         apiKeyProvider: @escaping () -> String? = { KeychainService.shared.getAPIKey() }) {
        self.model = model
        self.language = language
        self.translateTo = translateTo
        self.apiKeyProvider = apiKeyProvider
    }

    func start() async throws {
        guard let key = apiKeyProvider() else { throw LiveTranscriptionError.noAPIKey }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted: throw LiveTranscriptionError.microphonePermissionDenied
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw LiveTranscriptionError.microphonePermissionDenied
        default: break
        }

        openSocket(key: key)
        configureSession()
        receiveLoop()
        try startAudio()
    }

    private func openSocket(key: String) {
        let urlString = isTranslating
            ? "wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate"
            : "wss://api.openai.com/v1/realtime?intent=transcription"
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        // GA Realtime API: the beta `OpenAI-Beta: realtime=v1` header is gone — sending
        // it now makes the server reject the connection (beta_api_shape_disabled).
        let ws = URLSession.shared.webSocketTask(with: request)
        webSocket = ws
        ws.resume()
    }

    // MARK: - Test seam: drive from an audio file instead of the live mic

    /// Connect + configure the session WITHOUT starting microphone capture.
    /// Used by integration tests that feed audio from a fixture via `streamPCMFile`.
    func startSessionOnly() throws {
        guard let key = apiKeyProvider() else { throw LiveTranscriptionError.noAPIKey }
        openSocket(key: key)
        configureSession()
        receiveLoop()
    }

    /// Read an audio file, convert to 24kHz mono PCM16, stream it, and commit.
    func streamPCMFile(_ url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw LiveTranscriptionError.audioEngineFailed("could not allocate read buffer")
        }
        try file.read(into: buffer)
        guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
            throw LiveTranscriptionError.audioEngineFailed("could not create converter")
        }
        self.converter = converter
        if let data = Self.pcm16Data(from: buffer, to: targetFormat, using: converter) {
            send(["type": appendEventType, "audio": data.base64EncodedString()])
        }
        if !isTranslating { send(["type": "input_audio_buffer.commit"]) }
    }

    func stop() async -> String {
        // Stop capturing new audio first.
        if audioStarted {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioStarted = false
        }
        // Flush the trailing audio and wait for its transcript before closing, so
        // the end of the phrase isn't lost. Transcription: commit, then wait for the
        // `.completed` event (with a timeout). Translation: no commit/completed —
        // give trailing deltas a moment to arrive.
        if !isTranslating {
            send(["type": "input_audio_buffer.commit"])
            await awaitFinalTranscript(timeout: 3.0)
        } else {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
        // Now tear the socket down; flag it so the receive loop doesn't treat the
        // close as a "connection failed" error.
        isStopping = true
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        converter = nil
        return (confirmed + pending).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Wait for the post-commit `.completed` transcript, or `timeout` seconds,
    /// whichever comes first. Runs on the main actor, so the continuation and the
    /// event handler that resumes it never race.
    private func awaitFinalTranscript(timeout seconds: Double) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            finalContinuation = cont
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if let pending = finalContinuation { finalContinuation = nil; pending.resume() }
            }
        }
    }

    // MARK: - Session

    private func configureSession() {
        // Translation session: only the target output language is set; the source
        // language is auto-detected and the stream returns translated text.
        if let translateTo {
            send([
                "type": "session.update",
                "session": ["audio": ["output": ["language": translateTo]]]
            ])
            return
        }
        var transcription: [String: Any] = ["model": model]
        if let language { transcription["language"] = language }
        // GA shape: `session.update` with a typed transcription session and the audio
        // input config nested under `audio.input` (the beta used a flat
        // `transcription_session.update` with `input_audio_format`).
        send([
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24000],
                        "transcription": transcription
                    ]
                ]
            ]
        ])
    }

    // MARK: - Audio capture

    private func startAudio() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw LiveTranscriptionError.audioEngineFailed("could not create 24kHz PCM16 converter")
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.sendAudio(buffer)
            // Drive the live mic meter from the captured audio.
            let level = Self.rmsLevel(from: buffer)
            Task { @MainActor in self?.onAudioLevel?(level) }
        }
        engine.prepare()
        do {
            try engine.start()
            audioStarted = true
        } catch {
            throw LiveTranscriptionError.audioEngineFailed(error.localizedDescription)
        }
    }

    /// Runs on the audio render thread; converts and ships one buffer.
    private nonisolated func sendAudio(_ buffer: AVAudioPCMBuffer) {
        guard let converter = converter,
              let data = Self.pcm16Data(from: buffer, to: targetFormat, using: converter) else { return }
        send(["type": appendEventType, "audio": data.base64EncodedString()])
    }

    /// Normalized (0...1) RMS level of a captured buffer, for the live mic meter.
    nonisolated static func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let frames = Int(buffer.frameLength)
        let samples = channel[0]
        var sumSquares: Float = 0
        for i in 0..<frames { sumSquares += samples[i] * samples[i] }
        let rms = (sumSquares / Float(frames)).squareRoot()
        // Speech RMS sits roughly in 0.02...0.2; scale up and clamp for a lively meter.
        return min(1, rms * 8)
    }

    /// Pure conversion of an audio buffer to little-endian PCM16 bytes at the
    /// target format. Factored out for unit testing (Layer 2).
    nonisolated static func pcm16Data(from buffer: AVAudioPCMBuffer,
                                      to target: AVAudioFormat,
                                      using converter: AVAudioConverter) -> Data? {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var consumed = false
        var convError: NSError?
        converter.convert(to: out, error: &convError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard convError == nil, let channel = out.int16ChannelData, out.frameLength > 0 else { return nil }
        return Data(bytes: channel[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
    }

    // MARK: - WebSocket I/O

    private nonisolated func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(string)) { _ in }
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    // Ignore the socket closing when we tore it down intentionally.
                    if self.isStopping { return }
                    self.onError?(LiveTranscriptionError.connectionFailed(error.localizedDescription))
                case .success(let message):
                    if case .string(let text) = message { self.handleEvent(text) }
                    self.receiveLoop()
                }
            }
        }
    }

    private func handleEvent(_ text: String) {
        switch Self.parseEvent(text) {
        case .delta(let delta):
            pending += delta
            onPartial?((confirmed + pending).trimmingCharacters(in: .whitespacesAndNewlines))
        case .completed(let transcript):
            confirmed += transcript ?? pending
            pending = ""
            onPartial?(confirmed.trimmingCharacters(in: .whitespacesAndNewlines))
            // A completed transcript after our stop-commit is the signal that the
            // trailing audio has been transcribed — let stop() finish waiting.
            if let cont = finalContinuation { finalContinuation = nil; cont.resume() }
        case .failure(let message):
            // Server VAD auto-commits speech segments, so the explicit commit we send
            // on stop()/streamPCMFile often lands on an already-empty buffer. That
            // "buffer too small" error is expected and not worth surfacing.
            if message.contains("buffer too small") { break }
            onError?(LiveTranscriptionError.connectionFailed(message))
        case .ignored:
            break
        }
    }

    /// One decoded Realtime transcription event. Pure/`Equatable` for unit tests (Layer 1).
    enum RealtimeEvent: Equatable {
        case delta(String)
        case completed(String?)   // `transcript` may be absent (fall back to accumulated deltas)
        case failure(String)
        case ignored
    }

    /// Pure parse of a Realtime server event JSON string. No side effects.
    nonisolated static func parseEvent(_ text: String) -> RealtimeEvent {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return .ignored }

        switch type {
        case "conversation.item.input_audio_transcription.delta":
            if let delta = obj["delta"] as? String { return .delta(delta) }
            return .ignored
        case "conversation.item.input_audio_transcription.completed":
            return .completed(obj["transcript"] as? String)
        case "session.output_transcript.delta":
            // gpt-realtime-translate: append-only translated text fragments
            // (no separate completed event — deltas accumulate to the result).
            if let delta = obj["delta"] as? String { return .delta(delta) }
            return .ignored
        case "error":
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "realtime transcription error"
            return .failure(message)
        default:
            return .ignored
        }
    }
}
