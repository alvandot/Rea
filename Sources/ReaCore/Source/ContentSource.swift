import Foundation

/// A content source (MangaDex, local files, extension, …).
public protocol ContentSource: Sendable {
    var id: String { get }
    var name: String { get }
    var language: String { get }

    func popular(page: Int) async throws -> PagedResult<Series>
    func latest(page: Int) async throws -> PagedResult<Series>
    func search(_ query: String, page: Int) async throws -> PagedResult<Series>
    func series(remoteID: String) async throws -> Series
    func chapters(seriesRemoteID: String) async throws -> [Chapter]
    func pages(chapterRemoteID: String) async throws -> [PageResource]
}

public struct PagedResult<Element: Sendable>: Sendable {
    public var items: [Element]
    public var hasNext: Bool
    public init(items: [Element], hasNext: Bool) {
        self.items = items
        self.hasNext = hasNext
    }
}

public struct PageResource: Hashable, Sendable {
    public enum Origin: Hashable, Sendable {
        case remote(URL)
        case localFile(URL)
    }
    public var origin: Origin
    public var index: Int
    public var mimeType: String?

    public init(origin: Origin, index: Int, mimeType: String? = nil) {
        self.origin = origin
        self.index = index
        self.mimeType = mimeType
    }
}

public enum SourceError: Error, Equatable, Sendable {
    case notFound
    case unauthorized
    case network(String)
    case parse(String)
    case unsupported
}

/// Coordinates registered sources.
public actor SourceRegistry {
    private var sources: [String: any ContentSource] = [:]

    public init() {}

    public func register(_ source: any ContentSource) {
        sources[source.id] = source
    }

    public func source(id: String) -> (any ContentSource)? { sources[id] }

    public func all() -> [any ContentSource] { Array(sources.values) }

    public func globalSearch(_ query: String) async -> [Series] {
        await withTaskGroup(of: [Series].self) { group in
            for source in sources.values {
                group.addTask { (try? await source.search(query, page: 1).items) ?? [] }
            }
            var results: [Series] = []
            for await batch in group { results.append(contentsOf: batch) }
            return results
        }
    }
}
