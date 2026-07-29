import XCTest
@testable import Whisper

/// Pure-logic unit tests for the small helpers on `AppState` and its nested types:
/// language naming, the custom-terminology JSON codec, clipboard previews, and the
/// status-text mapping. These exercise deterministic logic only (no network/UI).
@MainActor
final class AppStateLogicTests: XCTestCase {

    // MARK: - languageName(for:)

    func testLanguageNameKnownCodes() {
        XCTAssertEqual(AppState.languageName(for: "en"), "English")
        XCTAssertEqual(AppState.languageName(for: "ru"), "Russian")
    }

    func testLanguageNameUnknownCodePassesThrough() {
        // Unknown codes fall back to the raw code (used verbatim in the prompt).
        XCTAssertEqual(AppState.languageName(for: "auto"), "auto")
        XCTAssertEqual(AppState.languageName(for: "de"), "de")
    }

    // MARK: - shouldTranslate

    /// Translation needs BOTH the toggle and a concrete target language. Previously a
    /// selected language alone was enough, which translated dictations unasked.
    func testShouldTranslateRequiresToggleAndConcreteLanguage() {
        let state = AppState(openAIService: MockOpenAIService(), pasteService: MockPaste())

        state.enableTranslation = false
        state.whisperLanguage = "ru"
        XCTAssertFalse(state.shouldTranslate, "toggle off → never translate")

        state.enableTranslation = true
        state.whisperLanguage = "auto"
        XCTAssertFalse(state.shouldTranslate, "Auto has no target language")

        state.whisperLanguage = "ru"
        XCTAssertTrue(state.shouldTranslate)
    }

    // MARK: - customTerminology JSON codec

    func testTerminologyRoundTrips() {
        let state = AppState(openAIService: MockOpenAIService(), pasteService: MockPaste())
        state.customTerminology = ["Sich", "WhisperKit", "Incode"]
        XCTAssertEqual(state.customTerminology, ["Sich", "WhisperKit", "Incode"])
        // Backed by a JSON string.
        XCTAssertTrue(state.customTerminologyJSON.contains("WhisperKit"))
    }

    func testTerminologyEmptyByDefaultAndOnMalformedJSON() {
        let state = AppState(openAIService: MockOpenAIService(), pasteService: MockPaste())
        XCTAssertEqual(state.customTerminology, [], "defaults to empty list")

        state.customTerminologyJSON = "not valid json {["
        XCTAssertEqual(state.customTerminology, [], "malformed JSON decodes to an empty list, never crashes")
    }

    func testTerminologyEmptyArrayJSON() {
        let state = AppState(openAIService: MockOpenAIService(), pasteService: MockPaste())
        state.customTerminologyJSON = "[]"
        XCTAssertEqual(state.customTerminology, [])
    }

    // MARK: - ClipboardContent

    func testClipboardHasContent() {
        XCTAssertFalse(AppState.ClipboardContent.empty.hasContent)
        XCTAssertTrue(AppState.ClipboardContent.text("x").hasContent)
        XCTAssertTrue(AppState.ClipboardContent.image(Data()).hasContent)
    }

    func testClipboardPreviewEmptyAndImage() {
        XCTAssertEqual(AppState.ClipboardContent.empty.preview, "Empty")
        XCTAssertEqual(AppState.ClipboardContent.image(Data()).preview, "📷 Image")
    }

    func testClipboardPreviewShortTextIsVerbatim() {
        XCTAssertEqual(AppState.ClipboardContent.text("hello").preview, "hello")
    }

    func testClipboardPreviewLongTextIsTruncatedWithEllipsis() {
        let long = String(repeating: "a", count: 60)
        let preview = AppState.ClipboardContent.text(long).preview
        XCTAssertTrue(preview.hasSuffix("..."), "long text is truncated with an ellipsis")
        XCTAssertEqual(preview.count, 53, "50 chars + the three-dot ellipsis")
    }

    func testClipboardPreviewExactlyFiftyCharsIsNotTruncated() {
        let exact = String(repeating: "b", count: 50)
        XCTAssertEqual(AppState.ClipboardContent.text(exact).preview, exact)
    }

    // MARK: - statusText

    func testStatusTextForEachState() {
        let state = AppState(openAIService: MockOpenAIService(), pasteService: MockPaste())

        state.processingState = .idle
        XCTAssertEqual(state.statusText, "Ready")
        state.processingState = .recording
        XCTAssertEqual(state.statusText, "Recording...")
        state.processingState = .transcribing
        XCTAssertEqual(state.statusText, "Transcribing...")
        state.processingState = .processing
        XCTAssertEqual(state.statusText, "Processing with GPT...")
        state.processingState = .showingResult("whatever")
        XCTAssertEqual(state.statusText, "Done")
        state.processingState = .error("boom")
        XCTAssertEqual(state.statusText, "Error: boom")
    }
}
