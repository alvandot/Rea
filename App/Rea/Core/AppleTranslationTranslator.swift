import Foundation
#if canImport(Translation)
import Translation
#endif

/// Bridges Apple's on-device Translation framework to `TextTranslator`.
///
/// `TranslationSession` only materializes inside a SwiftUI `.translationTask`,
/// so this adapter translates through a session supplied by the UI layer and
/// reports unavailability otherwise.
struct AppleTranslationTranslator: TextTranslator {
    private let sessionProvider: () -> Any?

    init(sessionProvider: @escaping () -> Any? = { nil }) {
        self.sessionProvider = sessionProvider
    }

    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        #if canImport(Translation)
        guard let session = sessionProvider() as? TranslationSession else {
            throw TranslationError.unavailable
        }
        let response = try await session.translate(text)
        return response.targetText
        #else
        throw TranslationError.unavailable
        #endif
    }
}
