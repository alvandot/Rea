import XCTest
@testable import ReaCore

private struct StubRecognizer: ImageTextRecognizer {
    let results: [RecognizedText]
    func recognizeText(in imageData: Data, preferredLanguages: [String]) async throws -> [RecognizedText] {
        results
    }
}

private struct CountingTranslator: TextTranslator {
    let counter: Counter
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        await counter.bump()
        return "T:\(text)"
    }
}

private actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}

private struct EchoTranslator: TextTranslator {
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        "\(target.code):\(text)"
    }
}

private struct StubTransport: HTTPTransport {
    let payload: Data
    let status: Int

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (payload, response)
    }
}

final class TranslationTests: XCTestCase {
    func testIdentityTranslator() async throws {
        let translator = IdentityTranslator()
        let result = try await translator.translate("hello", from: .english, to: .indonesian)
        XCTAssertEqual(result, "hello")
    }

    func testPageTranslationServiceBuildsBubbles() async throws {
        let recognized = [
            RecognizedText(string: "おはよう", boundingBox: CGRect(x: 0, y: 0, width: 0.2, height: 0.1), confidence: 0.9),
            RecognizedText(string: "   ", boundingBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.1), confidence: 0.5),
            RecognizedText(string: "おはよう", boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.1), confidence: 0.9)
        ]
        let service = PageTranslationService(
            recognizer: StubRecognizer(results: recognized),
            translator: EchoTranslator()
        )
        let bubbles = try await service.translatePage(imageData: Data(), from: .japanese, to: .english)
        XCTAssertEqual(bubbles.count, 2)
        XCTAssertEqual(bubbles[0].translated, "en:おはよう")
    }

    func testCachingTranslatorReusesResult() async throws {
        let counter = Counter()
        let upstream = CountingTranslator(counter: counter)
        let cache = CachingTranslator(upstream: upstream)
        _ = try await cache.translate("x", from: .english, to: .japanese)
        _ = try await cache.translate("x", from: .english, to: .japanese)
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testHTTPTextTranslatorParsesResponse() async throws {
        let payload = Data(#"{"translatedText":"halo"}"#.utf8)
        let config = HTTPTextTranslator.Configuration.libreTranslate(
            URL(string: "https://example.com/translate")!,
            apiKey: nil
        )
        let translator = HTTPTextTranslator(
            config: config,
            transport: StubTransport(payload: payload, status: 200)
        )
        let result = try await translator.translate("hello", from: .english, to: .indonesian)
        XCTAssertEqual(result, "halo")
    }

    func testHTTPTextTranslatorRejectsErrorStatus() async {
        let config = HTTPTextTranslator.Configuration.libreTranslate(
            URL(string: "https://example.com/translate")!,
            apiKey: nil
        )
        let translator = HTTPTextTranslator(
            config: config,
            transport: StubTransport(payload: Data(), status: 500)
        )
        do {
            _ = try await translator.translate("hello", from: .english, to: .indonesian)
            XCTFail("Expected failure")
        } catch let error as TranslationError {
            guard case .failed = error else { return XCTFail("Unexpected error") }
        } catch {
            XCTFail("Unexpected error type")
        }
    }
}
