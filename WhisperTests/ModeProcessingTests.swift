import XCTest
@testable import Whisper

/// Integration tests for AppState.process(_:mode:) — the shared pipeline that the
/// classic and live paths both run. Uses stubbed services (no network, no real
/// paste) so each recording mode's routing is verified end to end.
@MainActor
final class ModeProcessingTests: XCTestCase {

    /// A scratch defaults domain so tests never write into the user's real history.
    private var historyStore: UserDefaults!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: "WhisperTests.modeProcessing")
        historyStore = UserDefaults(suiteName: "WhisperTests.modeProcessing")!
        historyStore.removePersistentDomain(forName: "WhisperTests.modeProcessing")
    }

    private func makeState(_ api: MockOpenAIService, _ paste: MockPaste) -> AppState {
        let state = AppState(openAIService: api, pasteService: paste, historyStore: historyStore)
        state.whisperLanguage = "auto"   // no output-language translation by default
        state.enableTranslation = false  // translation is opt-in
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

        // The transcript is passed as delimited DATA (not a bare user message) so the
        // model can't treat it as a command — but the original text is still present.
        XCTAssertEqual(api.lastPostProcessText?.contains("raw dictation"), true,
                       "transcribe should refine the transcript")
        XCTAssertEqual(api.lastPostProcessText?.contains("<<<TEXT"), true,
                       "the transcript must be wrapped in data markers")
        XCTAssertEqual(api.lastPostProcessPrompt?.contains("not an assistant"), true,
                       "the system prompt must pin the model into a pure text-transformer role")
        XCTAssertEqual(paste.pasted, "Refined text.")
    }

    /// The original bug: dictating something that reads like a question/command made
    /// gpt-4o-mini answer it instead of cleaning it up. The hardened prompt must keep
    /// the dictation as data and never instruct the model to answer.
    func testTranscribeCommandLikeDictationIsNotTreatedAsCommand() async throws {
        let api = MockOpenAIService(); api.postProcessResult = "What is the capital of France?"
        let paste = MockPaste()
        let state = makeState(api, paste)

        try await state.process("what is the capital of France", mode: .transcribe)

        let system = try XCTUnwrap(api.lastPostProcessPrompt)
        let user = try XCTUnwrap(api.lastPostProcessText)
        XCTAssertTrue(system.contains("not an assistant"))
        XCTAssertTrue(system.lowercased().contains("never") && system.lowercased().contains("answer"),
                      "system prompt must forbid answering the text")
        XCTAssertTrue(user.contains("what is the capital of France"),
                      "the dictation must be passed through as data, verbatim")
        XCTAssertTrue(user.contains("Output only the transformed text"))
    }

    func testTranscribeModeTranslatesToOutputLanguage() async throws {
        let api = MockOpenAIService(); api.postProcessResult = "Перевод."
        let paste = MockPaste()
        let state = makeState(api, paste)
        state.enableGPTProcessing = false   // skip refinement; isolate the translation step
        state.enableTranslation = true
        state.whisperLanguage = "ru"        // output language → translate on stop

        try await state.process("hello world", mode: .transcribe)

        XCTAssertEqual(api.lastPostProcessText?.contains("hello world"), true,
                       "translation feeds the transcript through postProcess")
        XCTAssertEqual(api.lastPostProcessPrompt?.contains("not an assistant"), true,
                       "translation must also run through the hardened transformer prompt")
        XCTAssertEqual(api.lastPostProcessText?.contains("Russian"), true,
                       "the target language must be named in the instruction")
        XCTAssertEqual(paste.pasted, "Перевод.")
    }

    // MARK: - Translation toggle

    /// The bug this fixes: a selected LANGUAGE alone used to translate every dictation,
    /// even with post-processing off — silently rewriting (and often mangling) the text.
    func testTranslationOffLeavesTranscriptAloneEvenWithLanguageSelected() async throws {
        let api = MockOpenAIService()
        let paste = MockPaste()
        let state = makeState(api, paste)
        state.enableGPTProcessing = false
        state.enableTranslation = false     // the toggle, not the language, decides
        state.whisperLanguage = "ru"

        try await state.process("hello world", mode: .transcribe)

        XCTAssertFalse(state.shouldTranslate)
        XCTAssertNil(api.lastPostProcessText, "translation off → no model call at all")
        XCTAssertEqual(paste.pasted, "hello world", "the transcript is pasted verbatim")
    }

    func testTranslationOnWithAutoLanguageDoesNotTranslate() async throws {
        let api = MockOpenAIService()
        let paste = MockPaste()
        let state = makeState(api, paste)
        state.enableGPTProcessing = false
        state.enableTranslation = true
        state.whisperLanguage = "auto"      // nothing to translate into

        try await state.process("hello world", mode: .transcribe)

        XCTAssertFalse(state.shouldTranslate)
        XCTAssertNil(api.lastPostProcessText)
        XCTAssertEqual(paste.pasted, "hello world")
    }

    /// Refinement + translation must be one model pass. The second pass was where the
    /// model most often derailed (answering the dictation, re-translating, paraphrasing).
    func testRefineAndTranslateRunAsASinglePass() async throws {
        let api = MockOpenAIService(); api.postProcessResult = "Готовый текст."
        let paste = MockPaste()
        let state = makeState(api, paste)
        state.enableGPTProcessing = true
        state.formattingMode = .slack
        state.enableTranslation = true
        state.whisperLanguage = "ru"

        try await state.process("hello world", mode: .transcribe)

        XCTAssertEqual(api.postProcessCallCount, 1, "one pass, not refine-then-translate")
        let user = try XCTUnwrap(api.lastPostProcessText)
        XCTAssertTrue(user.contains("Slack message"), "formatting instruction is included")
        XCTAssertTrue(user.contains("Russian"), "translation instruction is included")
        XCTAssertFalse(user.contains("Keep the same language as the original text"),
                       "the keep-language rule must not contradict the translation")
        XCTAssertEqual(paste.pasted, "Готовый текст.")
    }

    // MARK: - Raw dictation history

    func testHistoryKeepsRawTranscriptAndProcessedResult() async throws {
        let api = MockOpenAIService(); api.postProcessResult = "Refined text."
        let state = makeState(api, MockPaste())

        try await state.process("raw dictation", mode: .transcribe)

        let entry = try XCTUnwrap(state.transcriptHistory.first)
        XCTAssertEqual(entry.raw, "raw dictation", "the untouched transcript is kept")
        XCTAssertEqual(entry.processed, "Refined text.")
        XCTAssertEqual(entry.mode, RecordingMode.transcribe.rawValue)
        XCTAssertTrue(entry.wasChanged)
    }

    /// The point of the history: when refinement/translation blows up, the dictation
    /// must still be recoverable instead of having to be spoken again.
    func testHistoryKeepsRawTranscriptWhenProcessingFails() async throws {
        let api = MockOpenAIService()
        api.postProcessError = OpenAIError.apiError("boom")
        let state = makeState(api, MockPaste())

        do {
            try await state.process("a long dictation", mode: .transcribe)
            XCTFail("processing should have thrown")
        } catch {}

        let entry = try XCTUnwrap(state.transcriptHistory.first)
        XCTAssertEqual(entry.raw, "a long dictation")
        XCTAssertNil(entry.processed, "a failed run keeps the raw text only")
    }

    func testHistoryIsNewestFirstAndSkipsEmptyTranscripts() async throws {
        let api = MockOpenAIService()
        let state = makeState(api, MockPaste())
        state.enableGPTProcessing = false

        try await state.process("first", mode: .transcribe)
        try await state.process("second", mode: .transcribe)
        try await state.process("   ", mode: .transcribe)

        XCTAssertEqual(state.transcriptHistory.map(\.raw), ["second", "first"],
                       "newest first, blank dictations not recorded")
    }

    func testHistoryPersistsAcrossAppStateInstancesAndCanBeCleared() async throws {
        let api = MockOpenAIService()
        let state = makeState(api, MockPaste())
        state.enableGPTProcessing = false
        try await state.process("remembered", mode: .transcribe)

        let reloaded = AppState(openAIService: api, pasteService: MockPaste(), historyStore: historyStore)
        XCTAssertEqual(reloaded.transcriptHistory.first?.raw, "remembered")

        reloaded.clearHistory()
        let afterClear = AppState(openAIService: api, pasteService: MockPaste(), historyStore: historyStore)
        XCTAssertTrue(afterClear.transcriptHistory.isEmpty)
    }

    func testHistoryIsCappedAtTheLimit() async throws {
        let api = MockOpenAIService()
        let state = makeState(api, MockPaste())
        state.enableGPTProcessing = false

        for i in 0..<(AppState.historyLimit + 5) {
            try await state.process("dictation \(i)", mode: .transcribe)
        }

        XCTAssertEqual(state.transcriptHistory.count, AppState.historyLimit)
        XCTAssertEqual(state.transcriptHistory.first?.raw,
                       "dictation \(AppState.historyLimit + 4)", "the newest survives")
    }

    func testCopyToClipboardGoesThroughPasteServiceWithoutPasting() {
        let paste = MockPaste()
        let state = makeState(MockOpenAIService(), paste)

        state.copyToClipboard("raw text")

        XCTAssertEqual(paste.copied, "raw text")
        XCTAssertNil(paste.pasted, "copying from History must never paste anywhere")
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

    // MARK: - Per-mode system prompts & routing

    func testAskModeSystemPromptAndWebSearchAndHistory() async throws {
        let api = MockOpenAIService(); api.chatResult = "Answer."
        let state = makeState(api, MockPaste())

        try await state.process("first question", mode: .askGPT)

        XCTAssertEqual(api.lastChatWebSearch, true, "Ask mode enables web search")
        XCTAssertEqual(api.lastChatModel, state.gptModel)
        XCTAssertTrue(api.lastChatSystemPrompt?.contains("voice assistant") == true)
        // The turn is recorded into history for the next message.
        XCTAssertEqual(state.conversationHistory.count, 2)
        XCTAssertEqual(state.conversationHistory.first?.role, "user")
        XCTAssertEqual(state.conversationHistory.first?.content, "first question")
        XCTAssertEqual(state.conversationHistory.last?.content, "Answer.")
    }

    func testRespondModeWritesReplyAndDoesNotAnswer() async throws {
        let api = MockOpenAIService(); api.chatResult = "Sure, see you then."
        let paste = MockPaste()
        let state = makeState(api, paste)
        state.useClipboardContext = true
        state.clipboardContent = .text("Can we meet Friday?")

        try await state.process("politely say yes", mode: .respond)

        let system = try XCTUnwrap(api.lastChatSystemPrompt)
        XCTAssertTrue(system.contains("response writer"))
        XCTAssertTrue(system.contains("DO NOT answer or analyze"),
                      "respond mode must write a reply, not answer the message itself")
        let user = try XCTUnwrap(api.lastChatUserMessage)
        XCTAssertTrue(user.contains("Can we meet Friday?"), "must include the message to respond to")
        XCTAssertTrue(user.contains("politely say yes"), "must include the how-to-respond instruction")
        XCTAssertEqual(paste.pasted, "Sure, see you then.")
    }

    func testRespondModeWithoutClipboardContextIgnoresClipboard() async throws {
        let api = MockOpenAIService(); api.chatResult = "Reply."
        let state = makeState(api, MockPaste())
        state.useClipboardContext = false
        state.clipboardContent = .text("SHOULD NOT APPEAR")

        try await state.process("write a greeting", mode: .respond)

        let user = try XCTUnwrap(api.lastChatUserMessage)
        XCTAssertFalse(user.contains("SHOULD NOT APPEAR"))
        XCTAssertTrue(user.contains("Write a response: write a greeting"))
    }

    func testCodeModeSystemPromptCarriesLanguageHint() async throws {
        let api = MockOpenAIService(); api.chatResult = "print(1)"
        let state = makeState(api, MockPaste())
        state.codeLanguageMode = .python

        try await state.process("print one", mode: .code)

        let system = try XCTUnwrap(api.lastChatSystemPrompt)
        XCTAssertTrue(system.contains("code generator"))
        XCTAssertTrue(system.localizedCaseInsensitiveContains("python"),
                      "code mode must inject the selected language hint")
        XCTAssertTrue(api.lastChatUserMessage?.contains("print one") == true)
    }

    func testProcessModeWithImageUsesVisionPath() async throws {
        let api = MockOpenAIService(); api.imageResult = "described"
        let paste = MockPaste()
        let state = makeState(api, paste)
        state.clipboardContent = .image(Data([0x1, 0x2, 0x3]))

        try await state.process("describe this", mode: .process)

        XCTAssertTrue(api.imageCalled, "image clipboard must route through the vision call")
        XCTAssertEqual(api.lastImageUserMessage, "describe this")
        XCTAssertTrue(api.lastImageSystemPrompt?.contains("image processor") == true)
        XCTAssertEqual(paste.pasted, "described")
    }

    func testProcessModeWithEmptyClipboardErrorsAndDoesNotPaste() async throws {
        let api = MockOpenAIService()
        let paste = MockPaste()
        let state = makeState(api, paste)
        state.clipboardContent = .empty

        try await state.process("do something", mode: .process)

        XCTAssertNil(paste.pasted, "nothing to process → must not paste")
        guard case .error(let message) = state.processingState else {
            return XCTFail("expected an error state, got \(state.processingState)")
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains("empty"))
    }

    func testTranscribeWithGPTProcessingDisabledPastesRawTranscript() async throws {
        let api = MockOpenAIService()
        let paste = MockPaste()
        let state = makeState(api, paste)
        state.enableGPTProcessing = false   // no refinement
        state.whisperLanguage = "auto"      // no translation

        try await state.process("raw words", mode: .transcribe)

        XCTAssertNil(api.lastPostProcessText, "with processing off, no postProcess call")
        XCTAssertEqual(paste.pasted, "raw words", "the raw transcript is pasted unchanged")
    }

    func testPasteModeWithAutoPasteOffShowsResultInChatInsteadOfPasting() async throws {
        let api = MockOpenAIService(); api.chatResult = "GENERATED"
        let paste = MockPaste()
        let state = makeState(api, paste)
        state.autoPasteResult = false
        state.lastTranscription = "the dictation"

        try await state.process("print one", mode: .code)

        XCTAssertNil(paste.pasted, "autoPaste off → show in chat, do not paste")
        guard case .showingResult(let shown) = state.processingState else {
            return XCTFail("expected .showingResult, got \(state.processingState)")
        }
        XCTAssertEqual(shown, "GENERATED")
        // The exchange is recorded so the chat panel can display it.
        XCTAssertEqual(state.conversationHistory.first?.content, "the dictation")
        XCTAssertEqual(state.conversationHistory.last?.content, "GENERATED")
    }
}

// MARK: - Stubs

final class MockOpenAIService: OpenAIServicing {
    var transcribeResult = "transcribed"
    var chatResult = "chat answer"
    var imageResult = "image result"
    var postProcessResult = "refined"

    private(set) var lastChatUserMessage: String?
    private(set) var lastChatSystemPrompt: String?
    private(set) var lastChatModel: String?
    private(set) var lastChatHistory: [(role: String, content: String)]?
    private(set) var lastChatWebSearch: Bool?
    private(set) var lastImageUserMessage: String?
    private(set) var lastImageSystemPrompt: String?
    private(set) var lastImageData: Data?
    private(set) var imageCalled = false
    private(set) var lastPostProcessText: String?
    private(set) var lastPostProcessPrompt: String?
    private(set) var lastPostProcessModel: String?
    private(set) var postProcessCallCount = 0
    /// When set, `postProcess` throws it — used to check the raw transcript survives.
    var postProcessError: Error?

    func transcribe(audioURL: URL, language: String?, prompt: String?) async throws -> String {
        transcribeResult
    }
    func chat(userMessage: String, history: [(role: String, content: String)], systemPrompt: String, model: String, enableWebSearch: Bool) async throws -> String {
        lastChatUserMessage = userMessage
        lastChatSystemPrompt = systemPrompt
        lastChatModel = model
        lastChatHistory = history
        lastChatWebSearch = enableWebSearch
        return chatResult
    }
    func chatWithImage(userMessage: String, imageData: Data, systemPrompt: String) async throws -> String {
        imageCalled = true
        lastImageUserMessage = userMessage
        lastImageSystemPrompt = systemPrompt
        lastImageData = imageData
        return imageResult
    }
    func postProcess(text: String, prompt: String, model: String) async throws -> String {
        lastPostProcessText = text
        lastPostProcessPrompt = prompt
        lastPostProcessModel = model
        postProcessCallCount += 1
        if let postProcessError { throw postProcessError }
        return postProcessResult
    }
}

final class MockPaste: Pasting {
    private(set) var pasted: String?
    private(set) var copied: String?
    func copyAndPaste(text: String) { pasted = text }
    func copyToClipboard(text: String) { copied = text }
}
