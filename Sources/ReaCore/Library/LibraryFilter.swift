import Foundation

/// Pure filtering for the library grid: status bucket + text query.
public struct LibraryFilter: Equatable, Sendable {
    public enum Scope: String, CaseIterable, Sendable {
        case all, reading, planToRead, completed, onHold, dropped, favorites

        public var title: String {
            switch self {
            case .all: return "All"
            case .reading: return "Reading"
            case .planToRead: return "Plan"
            case .completed: return "Completed"
            case .onHold: return "On Hold"
            case .dropped: return "Dropped"
            case .favorites: return "Favourites"
            }
        }

        public var status: ReadingStatus? {
            switch self {
            case .all, .favorites: return nil
            case .reading: return .reading
            case .planToRead: return .planToRead
            case .completed: return .completed
            case .onHold: return .onHold
            case .dropped: return .dropped
            }
        }
    }

    public var scope: Scope
    public var query: String

    public init(scope: Scope = .all, query: String = "") {
        self.scope = scope
        self.query = query
    }

    public func apply(to items: [Series]) -> [Series] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { matches($0, trimmedQuery: trimmed) }
    }

    public func matches(_ series: Series, trimmedQuery: String) -> Bool {
        if let status = scope.status, series.status != status { return false }
        if scope == .favorites && !series.isFavorite { return false }
        guard !trimmedQuery.isEmpty else { return true }
        if series.title.localizedCaseInsensitiveContains(trimmedQuery) { return true }
        if let author = series.author, author.localizedCaseInsensitiveContains(trimmedQuery) { return true }
        return series.categories.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    public var isActive: Bool {
        scope != .all || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
