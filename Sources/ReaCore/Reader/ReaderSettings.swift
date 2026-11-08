import Foundation

public struct ReaderSettings: Codable, Equatable, Sendable {
    public var verticalWebtoon: Bool
    public var rtl: Bool
    public var showOriginalText: Bool
    public var translationEnabled: Bool
    public var translationSourceCode: String
    public var translationTargetCode: String
    public var backgroundHex: String
    public var fitWidth: Bool

    public init(
        verticalWebtoon: Bool = true,
        rtl: Bool = true,
        showOriginalText: Bool = false,
        translationEnabled: Bool = false,
        translationSourceCode: String = "ja",
        translationTargetCode: String = "en",
        backgroundHex: String = "#000000",
        fitWidth: Bool = true
    ) {
        self.verticalWebtoon = verticalWebtoon
        self.rtl = rtl
        self.showOriginalText = showOriginalText
        self.translationEnabled = translationEnabled
        self.translationSourceCode = translationSourceCode
        self.translationTargetCode = translationTargetCode
        self.backgroundHex = backgroundHex
        self.fitWidth = fitWidth
    }

    public static let `default` = ReaderSettings()

    private static let key = "rea.readerSettings"

    public static func load(from defaults: UserDefaults = .standard) -> ReaderSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ReaderSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
