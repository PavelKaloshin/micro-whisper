import XCTest
@testable import Whisper

/// Pure-logic unit tests for the mode/formatting enums in `AppState.swift`.
/// These need no `AppState` instance (which is a `@MainActor` singleton wiring up
/// services), so they stay fast and side-effect free.
final class ModeLogicTests: XCTestCase {

    // MARK: - RecordingMode

    func testRecordingModeHotkeysAreUnique() {
        let keys = RecordingMode.allCases.map(\.hotkey)
        XCTAssertEqual(Set(keys).count, keys.count, "RecordingMode hotkeys must be unique")
    }

    func testRecordingModeUsesClipboard() {
        XCTAssertTrue(RecordingMode.respond.usesClipboard)
        XCTAssertTrue(RecordingMode.process.usesClipboard)
        XCTAssertFalse(RecordingMode.transcribe.usesClipboard)
        XCTAssertFalse(RecordingMode.askGPT.usesClipboard)
        XCTAssertFalse(RecordingMode.code.usesClipboard)
    }

    func testRecordingModeShowsResult() {
        XCTAssertFalse(RecordingMode.transcribe.showsResult, "transcribe pastes, never shows a result panel")
        for mode in [RecordingMode.askGPT, .respond, .code, .process] {
            XCTAssertTrue(mode.showsResult, "\(mode) should show a result")
        }
    }

    func testRecordingModeDisplayNamesNonEmpty() {
        for mode in RecordingMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty)
            XCTAssertFalse(mode.tooltip.isEmpty)
        }
    }

    // MARK: - FormattingMode

    func testFormattingModePromptsAreNonEmpty() {
        for mode in FormattingMode.allCases {
            XCTAssertFalse(
                mode.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(mode) must carry a non-empty GPT prompt"
            )
        }
    }

    func testFormattingModeHotkeysAreUnique() {
        let keys = FormattingMode.allCases.map(\.hotkey)
        XCTAssertEqual(Set(keys).count, keys.count, "FormattingMode hotkeys must be unique")
    }

    func testFormattingModeRawValuesRoundTrip() {
        for mode in FormattingMode.allCases {
            XCTAssertEqual(FormattingMode(rawValue: mode.rawValue), mode)
        }
    }

    // MARK: - CodeLanguageMode

    func testCodeLanguageHintsMentionTheLanguage() {
        XCTAssertTrue(CodeLanguageMode.python.promptHint.localizedCaseInsensitiveContains("python"))
        XCTAssertTrue(CodeLanguageMode.bash.promptHint.localizedCaseInsensitiveContains("bash"))
        XCTAssertFalse(CodeLanguageMode.auto.promptHint.isEmpty)
    }

    func testCodeLanguageHotkeysAreUnique() {
        let keys = CodeLanguageMode.allCases.map(\.hotkey)
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
