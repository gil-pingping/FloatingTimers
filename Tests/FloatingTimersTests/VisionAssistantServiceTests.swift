import XCTest
@testable import FloatingTimers

final class VisionAssistantServiceTests: XCTestCase {
    
    func testStreamResponseThrowsMissingModel() async {
        let service = VisionAssistantService()
        
        do {
            try await service.streamResponse(
                provider: .openAI,
                model: "",
                apiKey: "valid-key",
                prompt: "Hello",
                imageData: nil,
                mimeType: nil
            ) { _ in }
            XCTFail("Should throw missingModel")
        } catch VisionAssistantError.missingModel(let provider) {
            XCTAssertEqual(provider, AIProvider.openAI.label)
        } catch {
            XCTFail("Wrong error thrown: \(error)")
        }
    }
    
    func testStreamResponseThrowsMissingAPIKey() async {
        let service = VisionAssistantService()
        
        do {
            try await service.streamResponse(
                provider: .gemini,
                model: "gemini-model",
                apiKey: " ",
                prompt: "Hello",
                imageData: nil,
                mimeType: nil
            ) { _ in }
            XCTFail("Should throw missingAPIKey")
        } catch VisionAssistantError.missingAPIKey(let provider) {
            XCTAssertEqual(provider, AIProvider.gemini.label)
        } catch {
            XCTFail("Wrong error thrown: \(error)")
        }
    }

    func testGeminiStreamingSendsKeyInHeaderNotURL() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        let service = VisionAssistantService(session: URLSession(configuration: config))

        // ponytail: response outcome is irrelevant here; only the outgoing request is checked.
        try? await service.streamResponse(
            provider: .gemini,
            model: "gemini-model",
            apiKey: "secret-key",
            prompt: "Hello",
            imageData: nil,
            mimeType: nil
        ) { _ in }

        let request = try XCTUnwrap(CapturingURLProtocol.lastRequest)
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.contains(":streamGenerateContent"))
        XCTAssertTrue(url.contains("alt=sse"))
        XCTAssertFalse(url.contains("secret-key"))
        XCTAssertFalse(url.contains("key="))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "secret-key")
    }
}

private final class CapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("stub".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
