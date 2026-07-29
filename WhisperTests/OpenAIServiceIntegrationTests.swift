import XCTest
@testable import Whisper

/// Integration tests for the cloud REST path of `OpenAIService` — the classic
/// (non-realtime) Whisper transcription + chat-completions post-processing that the
/// Transcribe mode uses. These make real, billable network calls.
///
/// Opt-in: gated on RUN_OPENAI_TESTS=1 plus OPENAI_API_KEY. The macOS test host only
/// reads the scheme's env block (not the shell), so run via:
///   OPENAI_API_KEY=sk-…  make test-integration
/// (see scripts/run-integration-tests.sh). Uses WhisperTests/Fixtures/hello_en.wav.
/// Skips cleanly when the flag, key, or fixture is absent.
@MainActor
final class OpenAIServiceIntegrationTests: XCTestCase {

    private func service() throws -> OpenAIService {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["RUN_OPENAI_TESTS"] == "1", "Set RUN_OPENAI_TESTS=1 to run.")
        let key = try XCTUnwrap(env["OPENAI_API_KEY"], "Set OPENAI_API_KEY to run.")
        // Default baseURL + shared session → real network. Key from env, not Keychain.
        return OpenAIService(apiKeyProvider: { key })
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

    // MARK: - Whisper transcription (REST /audio/transcriptions)

    func testTranscribesEnglishFixture() async throws {
        let api = try service()
        let url = try fixtureURL("hello_en.wav")

        let text = try await api.transcribe(audioURL: url, language: "en", prompt: nil)

        let lower = text.lowercased()
        print("Whisper REST transcript: \(text)")
        // hello_en.wav says "The quick brown fox jumps over the lazy dog."
        XCTAssertTrue(lower.contains("quick brown fox"),
                      "unexpected transcript: \(text)")
        XCTAssertTrue(lower.contains("lazy dog"),
                      "unexpected transcript: \(text)")
    }

    // MARK: - Post-processing (chat completions) with the hardened refine prompt

    /// The original bug, end to end against the real model: a dictation that reads
    /// like a question must be cleaned up, NOT answered. The hardened prompt from
    /// AppState.makeRefinePrompt should keep the model in transform-only mode.
    func testHardenedRefineDoesNotAnswerCommandLikeText() async throws {
        let api = try service()
        let dictation = "what is two plus two"
        let p = AppState.makeRefinePrompt(
            instructions: "Fix grammar, punctuation, and capitalization. Keep the meaning.",
            text: dictation
        )

        let result = try await api.postProcess(text: p.user, prompt: p.system, model: "gpt-4o-mini")
        let lower = result.lowercased()

        print("Hardened refine result: \(result)")
        XCTAssertTrue(lower.contains("two"),
                      "cleanup must preserve the dictated words, got: \(result)")
        XCTAssertFalse(lower.contains("4") || lower.contains("four"),
                       "the model answered the question instead of cleaning it: \(result)")
    }

    /// Translation through the same hardened path should produce Russian (Cyrillic),
    /// not an answer or commentary.
    func testHardenedTranslateProducesRussian() async throws {
        let api = try service()
        let p = AppState.makeRefinePrompt(
            instructions: "Translate the following text into Russian. Return only the translation.",
            text: "Good morning, how are you?"
        )

        let result = try await api.postProcess(text: p.user, prompt: p.system, model: "gpt-4o-mini")

        print("Hardened translate result: \(result)")
        let hasCyrillic = result.unicodeScalars.contains { CharacterSet(charactersIn: "А"..."я").contains($0) }
        XCTAssertTrue(hasCyrillic, "expected Russian (Cyrillic) output, got: \(result)")
    }

    // MARK: - Full classic pipeline: transcribe → translate to Russian

    func testTranscribeThenTranslateFixtureToRussian() async throws {
        let api = try service()
        let url = try fixtureURL("hello_en.wav")

        let english = try await api.transcribe(audioURL: url, language: "en", prompt: nil)
        try XCTSkipIf(english.trimmingCharacters(in: .whitespaces).isEmpty, "empty transcript")

        let p = AppState.makeRefinePrompt(
            instructions: "Translate the following text into Russian. Return only the translation.",
            text: english
        )
        let russian = try await api.postProcess(text: p.user, prompt: p.system, model: "gpt-4o-mini")

        print("Pipeline: \(english) → \(russian)")
        let hasCyrillic = russian.unicodeScalars.contains { CharacterSet(charactersIn: "А"..."я").contains($0) }
        XCTAssertTrue(hasCyrillic, "expected Russian translation of the fixture, got: \(russian)")
        // "...lazy dog" → the Russian translation should mention the dog ("собак…").
        XCTAssertTrue(russian.lowercased().contains("собак"),
                      "translation should preserve the dog from the fixture, got: \(russian)")
    }
}
