import XCTest
@testable import Whisper

/// Layer 1 — pure unit tests for OpenAI Realtime event parsing. No network, no audio.
final class RealtimeParsingTests: XCTestCase {

    func testDeltaEvent() {
        let json = #"{"type":"conversation.item.input_audio_transcription.delta","delta":"hel"}"#
        XCTAssertEqual(OpenAIRealtimeLiveTranscriber.parseEvent(json), .delta("hel"))
    }

    func testCompletedWithTranscript() {
        let json = #"{"type":"conversation.item.input_audio_transcription.completed","transcript":"hello world"}"#
        XCTAssertEqual(OpenAIRealtimeLiveTranscriber.parseEvent(json), .completed("hello world"))
    }

    func testCompletedWithoutTranscript() {
        let json = #"{"type":"conversation.item.input_audio_transcription.completed"}"#
        XCTAssertEqual(OpenAIRealtimeLiveTranscriber.parseEvent(json), .completed(nil))
    }

    func testErrorEvent() {
        let json = #"{"type":"error","error":{"message":"bad audio"}}"#
        XCTAssertEqual(OpenAIRealtimeLiveTranscriber.parseEvent(json), .failure("bad audio"))
    }

    func testErrorEventWithoutMessageHasFallback() {
        let json = #"{"type":"error"}"#
        XCTAssertEqual(OpenAIRealtimeLiveTranscriber.parseEvent(json), .failure("realtime transcription error"))
    }

    func testUnknownTypeIgnored() {
        XCTAssertEqual(OpenAIRealtimeLiveTranscriber.parseEvent(#"{"type":"session.created"}"#), .ignored)
    }

    func testGarbageIgnored() {
        XCTAssertEqual(OpenAIRealtimeLiveTranscriber.parseEvent("not json at all"), .ignored)
    }
}
