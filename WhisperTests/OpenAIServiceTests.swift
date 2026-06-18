import XCTest
@testable import Whisper

/// Integration tests for `OpenAIService`: a stub `URLSession` (via `StubURLProtocol`)
/// and a fake API-key provider are injected, exercising the real request-building,
/// status-code handling, and JSON decoding paths without hitting the network.
final class OpenAIServiceTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.responder = nil
        super.tearDown()
    }

    private func makeService(key: String? = "test-key") -> OpenAIService {
        OpenAIService(
            baseURL: "https://stub.local/v1",
            session: StubURLProtocol.makeSession(),
            apiKeyProvider: { key }
        )
    }

    // MARK: - Success paths

    func testPostProcessParsesContent() async throws {
        StubURLProtocol.responder = { _ in
            (200, Data(#"{"choices":[{"message":{"role":"assistant","content":"fixed text"}}]}"#.utf8))
        }
        let out = try await makeService().postProcess(text: "raw", prompt: "p", model: "gpt-4o-mini")
        XCTAssertEqual(out, "fixed text")
    }

    func testChatParsesContent() async throws {
        StubURLProtocol.responder = { _ in
            (200, Data(#"{"choices":[{"message":{"role":"assistant","content":"hello"}}]}"#.utf8))
        }
        let out = try await makeService().chat(
            userMessage: "hi", history: [], systemPrompt: "s", model: "gpt-4o-mini"
        )
        XCTAssertEqual(out, "hello")
    }

    func testTranscribeParsesText() async throws {
        StubURLProtocol.responder = { _ in (200, Data(#"{"text":"hello world"}"#.utf8)) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stub-audio.m4a")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let out = try await makeService().transcribe(audioURL: tmp, language: "en", prompt: nil)
        XCTAssertEqual(out, "hello world")
    }

    func testChatSendsBearerAuthHeader() async throws {
        nonisolated(unsafe) var seenAuth: String?
        StubURLProtocol.responder = { req in
            seenAuth = req.value(forHTTPHeaderField: "Authorization")
            return (200, Data(#"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#.utf8))
        }
        _ = try await makeService(key: "sk-FAKE").chat(
            userMessage: "x", history: [], systemPrompt: "s", model: "m"
        )
        XCTAssertEqual(seenAuth, "Bearer sk-FAKE")
    }

    // MARK: - Error paths

    func testNoAPIKeyThrows() async {
        do {
            _ = try await makeService(key: nil).postProcess(text: "x", prompt: "p", model: "m")
            XCTFail("expected noAPIKey to throw")
        } catch let error as OpenAIError {
            guard case .noAPIKey = error else { return XCTFail("expected .noAPIKey, got \(error)") }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testHTTPErrorThrowsWithStatusCode() async {
        StubURLProtocol.responder = { _ in (500, Data("{}".utf8)) }
        do {
            _ = try await makeService().chat(userMessage: "x", history: [], systemPrompt: "s", model: "m")
            XCTFail("expected httpError")
        } catch let error as OpenAIError {
            guard case .httpError(let code) = error else { return XCTFail("expected .httpError, got \(error)") }
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testAPIErrorMessageIsSurfaced() async {
        StubURLProtocol.responder = { _ in
            (400, Data(#"{"error":{"message":"bad request detail"}}"#.utf8))
        }
        do {
            _ = try await makeService().chat(userMessage: "x", history: [], systemPrompt: "s", model: "m")
            XCTFail("expected apiError")
        } catch let error as OpenAIError {
            guard case .apiError(let message) = error else { return XCTFail("expected .apiError, got \(error)") }
            XCTAssertEqual(message, "bad request detail")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}
