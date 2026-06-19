import XCTest
import WhisperKit
@testable import Whisper

/// Layer 3 — on-device transcription of a recorded fixture via WhisperKit.
///
/// Opt-in (downloads the `base` model on first run):
///   RUN_WHISPERKIT_TESTS=1  and a fixture at WhisperTests/Fixtures/<name>.
/// Skips cleanly when the flag or fixture is absent, so the default suite stays
/// fast and offline.
final class WhisperKitFixtureTests: XCTestCase {

    func testTranscribesEnglishFixture() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_WHISPERKIT_TESTS"] == "1",
            "Set RUN_WHISPERKIT_TESTS=1 to run on-device WhisperKit integration tests."
        )
        let url = try fixtureURL("hello_en.wav")

        let pipe = try await WhisperKit(model: "base", verbose: false)
        let results = try await pipe.transcribe(audioPath: url.path)
        let text = results.map { $0.text }.joined(separator: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertFalse(text.isEmpty, "WhisperKit returned empty transcript")
        // Tighten this to the actual spoken phrase once the fixture is recorded.
        print("WhisperKit fixture transcript: \(text)")
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
