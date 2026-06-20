import XCTest
import AVFoundation
@testable import Whisper

/// Layer 2 — pure unit test for the PCM16 / resample conversion used before
/// streaming audio to the Realtime API. No network, no microphone.
final class AudioConversionTests: XCTestCase {

    func testConvertsFloat48kToPCM16_24k() throws {
        let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!

        let frames = AVAudioFrameCount(4800) // 0.1 s @ 48 kHz
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames))
        input.frameLength = frames
        let samples = try XCTUnwrap(input.floatChannelData)[0]
        for i in 0..<Int(frames) {
            samples[i] = sinf(Float(i) * 0.05) * 0.5  // a quiet sine
        }

        let converter = try XCTUnwrap(AVAudioConverter(from: inFormat, to: target))
        let data = try XCTUnwrap(
            OpenAIRealtimeLiveTranscriber.pcm16Data(from: input, to: target, using: converter)
        )

        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(data.count % MemoryLayout<Int16>.size, 0, "PCM16 byte count must be even")

        // 0.1 s downsampled to 24 kHz ≈ 2400 samples; allow converter slack.
        let sampleCount = data.count / MemoryLayout<Int16>.size
        XCTAssertGreaterThan(sampleCount, 2000)
        XCTAssertLessThan(sampleCount, 2600)
    }
}

/// Pure unit test for stripping Whisper special tokens / placeholders out of the
/// live transcript so they never reach the UI or the pasted text.
final class WhisperKitTranscriptCleanTests: XCTestCase {

    func testStripsSpecialTokens() {
        let raw = "<|startoftranscript|><|ru|><|transcribe|><|0.00|> привет мир<|endoftext|>"
        XCTAssertEqual(WhisperKitLiveTranscriber.cleanTranscript(raw), "привет мир")
    }

    func testStripsBlankAudioAndPlaceholder() {
        XCTAssertEqual(WhisperKitLiveTranscriber.cleanTranscript("[BLANK_AUDIO]"), "")
        XCTAssertEqual(WhisperKitLiveTranscriber.cleanTranscript("Waiting for speech..."), "")
    }

    func testCollapsesWhitespaceAndKeepsPlainText() {
        XCTAssertEqual(WhisperKitLiveTranscriber.cleanTranscript("  hello   world  "), "hello world")
        XCTAssertEqual(WhisperKitLiveTranscriber.cleanTranscript("the quick brown fox"), "the quick brown fox")
    }
}
