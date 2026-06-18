import Foundation

/// A `URLProtocol` that intercepts every request on its session and returns a
/// canned response supplied per test. This is the injection point for the
/// `OpenAIService` integration tests — no real network is touched.
final class StubURLProtocol: URLProtocol {
    /// Set this before each test. Given the outgoing request, return an HTTP
    /// status code and a response body, or throw to simulate a transport error.
    nonisolated(unsafe) static var responder: ((URLRequest) throws -> (status: Int, body: Data))?

    /// A `URLSession` wired to use only this stub protocol.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = StubURLProtocol.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, body) = try responder(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
