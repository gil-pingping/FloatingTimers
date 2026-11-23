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
}
