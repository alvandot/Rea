import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Injectable HTTP transport so services stay testable.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) {
        self.session = session
    }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// Remote translator speaking the LibreTranslate / DeepL-style JSON contract.
public struct HTTPTextTranslator: TextTranslator {
    public struct Configuration: Sendable {
        public var endpoint: URL
        public var apiKey: String?
        public var apiKeyField: String
        public var requestField: String
        public var responseField: String

        public init(
            endpoint: URL,
            apiKey: String? = nil,
            apiKeyField: String = "api_key",
            requestField: String = "q",
            responseField: String = "translatedText"
        ) {
            self.endpoint = endpoint
            self.apiKey = apiKey
            self.apiKeyField = apiKeyField
            self.requestField = requestField
            self.responseField = responseField
        }

        public static func libreTranslate(_ url: URL, apiKey: String?) -> Configuration {
            Configuration(endpoint: url, apiKey: apiKey, apiKeyField: "api_key",
                          requestField: "q", responseField: "translatedText")
        }
    }

    private let config: Configuration
    private let transport: any HTTPTransport

    public init(config: Configuration, transport: any HTTPTransport) {
        self.config = config
        self.transport = transport
    }

    public func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        guard !text.isEmpty else { return "" }
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var body: [String: String] = [
            config.requestField: text,
            "source": source.code,
            "target": target.code,
            "format": "text"
        ]
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            body[config.apiKeyField] = apiKey
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw TranslationError.failed("HTTP \(response.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translated = json[config.responseField] as? String else {
            throw TranslationError.failed("unexpected response")
        }
        return translated
    }
}
