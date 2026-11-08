import Foundation

#if canImport(JavaScriptCore)
/// Adapts a JS extension (`rea.source.*`) to `ContentSource`.
public struct JSContentSource: ContentSource {
    public nonisolated let id: String
    public nonisolated let name: String
    public nonisolated let language: String

    private let engine: JSEngine

    public init(manifest: ExtensionManifest, engine: JSEngine) {
        self.id = "ext.\(manifest.id)"
        self.name = manifest.name
        self.language = manifest.language
        self.engine = engine
    }

    public func popular(page: Int) async throws -> PagedResult<Series> {
        try await paged(fn: "popular", page: page)
    }

    public func latest(page: Int) async throws -> PagedResult<Series> {
        try await paged(fn: "latest", page: page)
    }

    public func search(_ query: String, page: Int) async throws -> PagedResult<Series> {
        try await paged(fn: "search", page: page, extra: [query])
    }

    public func series(remoteID: String) async throws -> Series {
        let raw = try await engine.call("series", args: [remoteID])
        guard let dict = raw as? [String: Any],
              let series = Self.decodeSeries(dict, sourceID: id) else {
            throw ExtensionError.invalidResult
        }
        return series
    }

    public func chapters(seriesRemoteID: String) async throws -> [Chapter] {
        let raw = try await engine.call("chapters", args: [seriesRemoteID])
        guard let list = raw as? [Any] else { throw ExtensionError.invalidResult }
        return list.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            return Self.decodeChapter(dict, seriesRemoteID: seriesRemoteID, sourceID: id)
        }
    }

    public func pages(chapterRemoteID: String) async throws -> [PageResource] {
        let raw = try await engine.call("pages", args: [chapterRemoteID])
        guard let list = raw as? [Any] else { throw ExtensionError.invalidResult }
        return list.enumerated().compactMap { index, item in
            guard let dict = item as? [String: Any],
                  let urlString = dict["url"] as? String,
                  let url = URL(string: urlString) else { return nil }
            return PageResource(origin: .remote(url), index: index)
        }
    }

    // MARK: - Helpers

    private func paged(fn: String, page: Int, extra: [Any] = []) async throws -> PagedResult<Series> {
        let raw = try await engine.call(fn, args: extra + [page])
        guard let dict = raw as? [String: Any] else { throw ExtensionError.invalidResult }
        let items = (dict["items"] as? [Any] ?? []).compactMap { item -> Series? in
            guard let s = item as? [String: Any] else { return nil }
            return Self.decodeSeries(s, sourceID: id)
        }
        return PagedResult(items: items, hasNext: dict["hasNext"] as? Bool ?? false)
    }

    private static func decodeSeries(_ dict: [String: Any], sourceID: String) -> Series? {
        guard let remoteID = dict["remoteID"] as? String, let title = dict["title"] as? String else { return nil }
        return Series(
            id: StableID.uuid(sourceID: sourceID, remoteID: remoteID),
            sourceID: sourceID,
            remoteID: remoteID,
            title: title,
            author: dict["author"] as? String,
            artist: dict["artist"] as? String,
            summary: dict["summary"] as? String,
            coverURL: (dict["coverURL"] as? String).flatMap(URL.init(string:)),
            status: (dict["status"] as? String).flatMap(ReadingStatus.init(rawValue:)) ?? .planToRead,
            rating: (dict["rating"] as? String).flatMap(ContentRating.init(rawValue:)) ?? .safe,
            categories: dict["categories"] as? [String] ?? []
        )
    }

    private static func decodeChapter(_ dict: [String: Any], seriesRemoteID: String, sourceID: String) -> Chapter? {
        guard let remoteID = dict["remoteID"] as? String, let name = dict["name"] as? String else { return nil }
        let number = (dict["number"] as? Double) ?? Double(dict["number"] as? String ?? "") ?? 0
        let uploaded: Date? = {
            guard let s = dict["uploadedAt"] as? String else { return nil }
            return ISO8601DateFormatter().date(from: s)
        }()
        return Chapter(
            id: StableID.uuid(sourceID: sourceID, remoteID: remoteID),
            seriesID: StableID.uuid(sourceID: sourceID, remoteID: seriesRemoteID),
            sourceID: sourceID,
            remoteID: remoteID,
            name: name,
            number: number,
            uploadedAt: uploaded,
            pageCount: dict["pageCount"] as? Int
        )
    }
}
#endif
