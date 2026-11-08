import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A language tag plus display name.
public struct Language: Hashable, Sendable, Codable {
    public let code: String
    public let name: String
    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
    public static let japanese = Language(code: "ja", name: "Japanese")
    public static let english = Language(code: "en", name: "English")
    public static let indonesian = Language(code: "id", name: "Indonesian")
}

public enum TranslationError: Error, Equatable, Sendable {
    case unavailable
    case failed(String)
    case emptyInput
}

/// Converts recognized text from one language to another.
public protocol TextTranslator: Sendable {
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String
}

/// Runs OCR over an image and returns text plus normalized boxes.
public protocol ImageTextRecognizer: Sendable {
    func recognizeText(in imageData: Data, preferredLanguages: [String]) async throws -> [RecognizedText]
}

public struct RecognizedText: Hashable, Sendable {
    public var string: String
    /// Normalized bounding box (0…1) in image space, origin top-left.
    public var boundingBox: CGRect
    public var confidence: Float

    public init(string: String, boundingBox: CGRect, confidence: Float) {
        self.string = string
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// A translated bubble ready for overlay rendering.
public struct TranslatedBubble: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var original: String
    public var translated: String
    public var boundingBox: CGRect

    public init(id: UUID = UUID(), original: String, translated: String, boundingBox: CGRect) {
        self.id = id
        self.original = original
        self.translated = translated
        self.boundingBox = boundingBox
    }
}

/// Coordinates OCR + translation into overlay bubbles for one page.
public struct PageTranslationService: Sendable {
    private let recognizer: any ImageTextRecognizer
    private let translator: any TextTranslator

    public init(recognizer: any ImageTextRecognizer, translator: any TextTranslator) {
        self.recognizer = recognizer
        self.translator = translator
    }

    public func translatePage(
        imageData: Data,
        from source: Language,
        to target: Language
    ) async throws -> [TranslatedBubble] {
        let recognized = try await recognizer.recognizeText(in: imageData, preferredLanguages: [source.code])
        var bubbles: [TranslatedBubble] = []
        var seen: [String: String] = [:]

        for text in recognized {
            let trimmed = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Duplicate bubbles (same source text) reuse the earlier translation.
            if let cached = seen[trimmed] {
                bubbles.append(TranslatedBubble(original: trimmed, translated: cached, boundingBox: text.boundingBox))
                continue
            }
            let translated = try await translator.translate(trimmed, from: source, to: target)
            seen[trimmed] = translated
            bubbles.append(TranslatedBubble(original: trimmed, translated: translated, boundingBox: text.boundingBox))
        }
        return bubbles
    }
}

/// Pass-through translator used when no provider is available.
public struct IdentityTranslator: TextTranslator {
    public init() {}
    public func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        text
    }
}

/// Memoizing wrapper around any translator.
public actor CachingTranslator: TextTranslator {
    private let upstream: any TextTranslator
    private var cache: [String: String] = [:]
    private let limit: Int

    public init(upstream: any TextTranslator, limit: Int = 512) {
        self.upstream = upstream
        self.limit = limit
    }

    public func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        let key = "\(source.code)|\(target.code)|\(text)"
        if let cached = cache[key] { return cached }
        let result = try await upstream.translate(text, from: source, to: target)
        if cache.count >= limit { cache.removeAll(keepingCapacity: true) }
        cache[key] = result
        return result
    }
}
