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

    // MARK: - Request building (body inspected via the stubbed stream)

    /// Drains the streamed request body (URLProtocol delivers POST bodies via
    /// `httpBodyStream`, not `httpBody`).
    private func body(of req: URLRequest) -> String {
        guard let stream = req.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 64 * 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buf, maxLength: size)
            if read <= 0 { break }
            data.append(buf, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }

    func testTranscribeSendsLanguagePromptAndDerivedFilename() async throws {
        nonisolated(unsafe) var sentBody = ""
        nonisolated(unsafe) var contentType: String?
        StubURLProtocol.responder = { req in
            sentBody = self.body(of: req)
            contentType = req.value(forHTTPHeaderField: "Content-Type")
            return (200, Data(#"{"text":"ok"}"#.utf8))
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stub-audio.wav")
        try Data([0x00, 0x01]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = try await makeService().transcribe(audioURL: tmp, language: "en", prompt: "Technical terms: Sich")

        XCTAssertTrue(contentType?.hasPrefix("multipart/form-data") == true)
        XCTAssertTrue(sentBody.contains("name=\"model\""))
        XCTAssertTrue(sentBody.contains("whisper-1"))
        XCTAssertTrue(sentBody.contains("name=\"language\""), "language part must be present")
        XCTAssertTrue(sentBody.contains("en"))
        XCTAssertTrue(sentBody.contains("name=\"prompt\""), "prompt part must be present")
        XCTAssertTrue(sentBody.contains("Technical terms: Sich"))
        // The .wav fixture must be uploaded as .wav, not the old hardcoded .m4a.
        XCTAssertTrue(sentBody.contains("filename=\"audio.wav\""), "filename must follow the file extension")
        XCTAssertTrue(sentBody.contains("Content-Type: audio/wav"))
    }

    func testTranscribeOmitsLanguageAndPromptWhenNil() async throws {
        nonisolated(unsafe) var sentBody = ""
        StubURLProtocol.responder = { req in
            sentBody = self.body(of: req)
            return (200, Data(#"{"text":"ok"}"#.utf8))
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stub-audio.m4a")
        try Data([0x00]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = try await makeService().transcribe(audioURL: tmp, language: nil, prompt: nil)

        XCTAssertFalse(sentBody.contains("name=\"language\""))
        XCTAssertFalse(sentBody.contains("name=\"prompt\""))
        XCTAssertTrue(sentBody.contains("filename=\"audio.m4a\""))
    }

    func testChatWebSearchSwapsModelAndAddsSearchOptions() async throws {
        nonisolated(unsafe) var sentBody = ""
        StubURLProtocol.responder = { req in
            sentBody = self.body(of: req)
            return (200, Data(#"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#.utf8))
        }
        _ = try await makeService().chat(
            userMessage: "x", history: [], systemPrompt: "s", model: "gpt-4o-mini", enableWebSearch: true
        )
        XCTAssertTrue(sentBody.contains("gpt-4o-search-preview"), "web search swaps to the search model")
        XCTAssertTrue(sentBody.contains("web_search_options"))
        XCTAssertFalse(sentBody.contains("gpt-4o-mini"), "the passed model is overridden when web search is on")
    }

    func testChatIncludesHistoryAndUsesGivenModelWithoutWebSearch() async throws {
        nonisolated(unsafe) var sentBody = ""
        StubURLProtocol.responder = { req in
            sentBody = self.body(of: req)
            return (200, Data(#"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#.utf8))
        }
        _ = try await makeService().chat(
            userMessage: "now", history: [(role: "user", content: "earlier")],
            systemPrompt: "s", model: "gpt-4o-mini", enableWebSearch: false
        )
        XCTAssertTrue(sentBody.contains("gpt-4o-mini"))
        XCTAssertFalse(sentBody.contains("web_search_options"))
        XCTAssertTrue(sentBody.contains("earlier"), "prior history turn must be sent")
        XCTAssertTrue(sentBody.contains("now"))
    }

    func testChatWithImageSendsBase64DataURL() async throws {
        nonisolated(unsafe) var sentBody = ""
        StubURLProtocol.responder = { req in
            sentBody = self.body(of: req)
            return (200, Data(#"{"choices":[{"message":{"role":"assistant","content":"described"}}]}"#.utf8))
        }
        let out = try await makeService().chatWithImage(
            userMessage: "what is this", imageData: Data([0xAB, 0xCD]), systemPrompt: "s"
        )
        XCTAssertEqual(out, "described")
        // JSONSerialization escapes the slash (data:image\/png), so match slash-agnostic
        // parts: the base64 marker and the actual encoded bytes ([0xAB,0xCD] → "q80=").
        XCTAssertTrue(sentBody.contains("base64,"), "image must be sent as a base64 data URL")
        XCTAssertTrue(sentBody.contains("q80="), "the image bytes must be base64-encoded into the payload")
        XCTAssertTrue(sentBody.contains("what is this"))
    }

    // MARK: - Pure helpers

    func testAudioMIMETypeMapping() {
        XCTAssertEqual(OpenAIService.audioMIMEType(forExtension: "wav"), "audio/wav")
        XCTAssertEqual(OpenAIService.audioMIMEType(forExtension: "m4a"), "audio/m4a")
        XCTAssertEqual(OpenAIService.audioMIMEType(forExtension: "mp3"), "audio/mpeg")
        XCTAssertEqual(OpenAIService.audioMIMEType(forExtension: "flac"), "audio/flac")
        XCTAssertEqual(OpenAIService.audioMIMEType(forExtension: "WAV"), "audio/wav", "extension match is case-insensitive")
        XCTAssertEqual(OpenAIService.audioMIMEType(forExtension: "xyz"), "audio/m4a", "unknown falls back to m4a")
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
