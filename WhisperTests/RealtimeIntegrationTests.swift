import XCTest
import AVFoundation
@testable import Whisper

/// Layer 4 — end-to-end OpenAI Realtime transcription: connect, stream a fixture
/// audio file (no live mic), and assert a non-empty transcript comes back.
///
/// Opt-in (real network + cost):
///   OPENAI_API_KEY=sk-…  RUN_REALTIME_TESTS=1  and WhisperTests/Fixtures/hello_en.wav.
/// Skips cleanly otherwise.
@MainActor
final class RealtimeIntegrationTests: XCTestCase {

    func testStreamsFixtureAndReceivesTranscript() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["RUN_REALTIME_TESTS"] == "1", "Set RUN_REALTIME_TESTS=1 to run.")
        let key = try XCTUnwrap(env["OPENAI_API_KEY"], "Set OPENAI_API_KEY to run.")
        let url = try fixtureURL("hello_en.wav")

        let transcriber = OpenAIRealtimeLiveTranscriber(
            model: "gpt-4o-transcribe",
            language: "en",
            apiKeyProvider: { key }
        )
        var latest = ""
        transcriber.onPartial = { latest = $0 }

        try transcriber.startSessionOnly()
        try transcriber.streamPCMFile(url)
        try await Task.sleep(nanoseconds: 6_000_000_000) // let events arrive
        let final = await transcriber.stop()

        XCTAssertFalse(final.isEmpty && latest.isEmpty, "expected some transcript from Realtime API")
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
