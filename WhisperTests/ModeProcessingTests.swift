import XCTest
@testable import Whisper

/// Integration tests for AppState.process(_:mode:) — the shared pipeline that the
/// classic and live paths both run. Uses stubbed services (no network, no real
/// paste) so each recording mode's routing is verified end to end.
@MainActor
final class ModeProcessingTests: XCTestCase {

    private func makeState(_ api: MockOpenAIService, _ paste: MockPaste) -> AppState {
        let state = AppState(openAIService: api, pasteService: paste)
        state.whisperLanguage = "auto"   // no output-language translation by default
        state.autoPasteResult = true
        state.enableGPTProcessing = true
        return state
    }

    func testAskModeShowsAnswerAndDoesNotPaste() async throws {
        let api = MockOpenAIService(); api.chatResult = "Four."
        let paste = MockPaste()
        let state = makeState(api, paste)

        try await state.process("what is two plus two", mode: .askGPT)

        XCTAssertEqual(api.lastChatUserMessage, "what is two plus two")
        XCTAssertNil(paste.pasted, "Ask shows a result panel, it must not paste")
        guard case .showingResult(let text) = state.processingState else {
            return XCTFail("Ask should end in .showingResult, got \(state.processingState)")
        }
        XCTAssertEqual(text, "Four.")
    }

    func testTranscribeModePastesRefinedText() async throws {
        let api = MockOpenAIService(); api.postProcessResult = "Refined text."
        let paste = MockPaste()
        let state = makeState(api, paste)

        try await state.process("raw dictation", mode: .transcribe)

        XCTAssertEqual(api.lastPostProcessText, "raw dictation", "transcribe should refine the transcript")
        XCTAssertEqual(paste.pasted, "Refined text.")
    }

    func testTranscribeModeTranslatesToOutputLanguage() async throws {
        let api = MockOpenAIService(); api.postProcessResult = "Перевод."
        let paste = MockPaste()
        let state = makeState(api, paste)
        state.enableGPTProcessing = false   // skip refinement; isolate the translation step
        state.whisperLanguage = "ru"        // output language → translate on stop

        try await state.process("hello world", mode: .transcribe)

        XCTAssertEqual(api.lastPostProcessText, "hello world", "translation feeds the transcript through postProcess")
        XCTAssertEqual(paste.pasted, "Перевод.")
    }

    func testCodeModePastesGeneratedCode() async throws {
        let api = MockOpenAIService(); api.chatResult = "print(1)"
        let paste = MockPaste()
        let state = makeState(api, paste)

        try await state.process("print one", mode: .code)

        XCTAssertEqual(paste.pasted, "print(1)")
    }

    func testProcessModeUsesClipboardAndPastes() async throws {
        let api = MockOpenAIService(); api.chatResult = "PROCESSED"
        let paste = MockPaste()
        let state = makeState(api, paste)
        state.useClipboardContext = true
        state.clipboardContent = .text("clipboard body")

        try await state.process("summarize this", mode: .process)

        XCTAssertEqual(paste.pasted, "PROCESSED")
        XCTAssertTrue(api.lastChatUserMessage?.contains("clipboard body") == true,
                      "process mode should include the clipboard content in the prompt")
    }
}

// MARK: - Stubs

final class MockOpenAIService: OpenAIServicing {
    var transcribeResult = "transcribed"
    var chatResult = "chat answer"
    var imageResult = "image result"
    var postProcessResult = "refined"

    private(set) var lastChatUserMessage: String?
    private(set) var lastPostProcessText: String?

    func transcribe(audioURL: URL, language: String?, prompt: String?) async throws -> String {
        transcribeResult
    }
    func chat(userMessage: String, history: [(role: String, content: String)], systemPrompt: String, model: String, enableWebSearch: Bool) async throws -> String {
        lastChatUserMessage = userMessage
        return chatResult
    }
    func chatWithImage(userMessage: String, imageData: Data, systemPrompt: String) async throws -> String {
        imageResult
    }
    func postProcess(text: String, prompt: String, model: String) async throws -> String {
        lastPostProcessText = text
        return postProcessResult
    }
}

final class MockPaste: Pasting {
    private(set) var pasted: String?
    private(set) var copied: String?
    func copyAndPaste(text: String) { pasted = text }
    func copyToClipboard(text: String) { copied = text }
}
