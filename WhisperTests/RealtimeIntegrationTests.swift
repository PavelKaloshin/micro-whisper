import XCTest
import AVFoundation
@testable import Whisper

/// Layer 4 — end-to-end OpenAI Realtime transcription: connect, stream a fixture
/// audio file (no live mic), and assert a non-empty transcript comes back.
///
/// Opt-in (real network + cost). The gate is the RUN_REALTIME_TESTS=1 env var plus
/// OPENAI_API_KEY, but the macOS test host only reads the scheme's env block, not the
/// shell — so run it via:
///   OPENAI_API_KEY=sk-…  make test-integration
/// (see scripts/run-integration-tests.sh). Needs WhisperTests/Fixtures/hello_en.wav.
/// Skips cleanly when the flag is absent.
@MainActor
final class RealtimeIntegrationTests: XCTestCase {

    func testStreamsFixtureAndReceivesTranscript() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["RUN_REALTIME_TESTS"] == "1", "Set RUN_REALTIME_TESTS=1 to run.")
        let key = try XCTUnwrap(env["OPENAI_API_KEY"], "Set OPENAI_API_KEY to run.")
        let url = try fixtureURL("hello_en.wav")

        let transcriber = OpenAIRealtimeLiveTranscriber(
            model: "gpt-realtime-whisper",
            language: "en",
            apiKeyProvider: { key }
        )
        var latest = ""
        var transcriberError: String?
        transcriber.onPartial = { latest = $0 }
        transcriber.onError = { transcriberError = $0.localizedDescription }

        try transcriber.startSessionOnly()
        try transcriber.streamPCMFile(url)
        try await Task.sleep(nanoseconds: 6_000_000_000) // let events arrive
        let final = await transcriber.stop()

        XCTAssertFalse(
            final.isEmpty && latest.isEmpty,
            "expected some transcript from Realtime API; transcriber error: \(transcriberError ?? "none")"
        )
        print("Realtime transcript: final=\(final) latest=\(latest)")
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let url = dir.appendingPathComponent(name)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: url.path),
            "Missing fixture \(name) — record a short clip into WhisperTests/Fixtures/."
        )
        return url
    }
}
