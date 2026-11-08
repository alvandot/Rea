import Foundation

enum TranslationProvider: String, CaseIterable, Identifiable, Sendable {
    case apple
    case remote

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "On-device (Apple)"
        case .remote: return "Remote (LibreTranslate/DeepL)"
        }
    }

    static let key = "rea.translation.provider"
    static let endpointKey = "rea.translation.endpoint"
    static let apiKeyKey = "rea.translation.apiKey"
}

/// Reads tracker tokens written by `OAuthCoordinator`.
struct DefaultsTokenProvider: TokenProvider {
    let tokenKey: String
    let refreshKey: String

    func accessToken() async throws -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    func refresh() async throws -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }
}
