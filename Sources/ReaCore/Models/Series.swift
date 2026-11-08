import Foundation

public enum ReadingStatus: String, Codable, CaseIterable, Sendable {
    case reading, planToRead, completed, onHold, dropped

    public var displayName: String {
        switch self {
        case .reading: return "Reading"
        case .planToRead: return "Plan to Read"
        case .completed: return "Completed"
        case .onHold: return "On Hold"
        case .dropped: return "Dropped"
        }
    }
}

public enum ContentRating: String, Codable, CaseIterable, Sendable {
    case safe, suggestive, erotica, pornographic

    public var displayName: String {
        switch self {
        case .safe: return "Safe"
        case .suggestive: return "Suggestive"
        case .erotica: return "Erotica"
        case .pornographic: return "Adult"
        }
    }
}

public struct Series: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var sourceID: String
    public var remoteID: String
    public var title: String
    public var author: String?
    public var artist: String?
    public var summary: String?
    public var coverURL: URL?
    public var status: ReadingStatus
    public var rating: ContentRating
    public var categories: [String]
    public var lastUpdated: Date?
    public var isFavorite: Bool

    public init(
        id: UUID = UUID(),
        sourceID: String,
        remoteID: String,
        title: String,
        author: String? = nil,
        artist: String? = nil,
        summary: String? = nil,
        coverURL: URL? = nil,
        status: ReadingStatus = .planToRead,
        rating: ContentRating = .safe,
        categories: [String] = [],
        lastUpdated: Date? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.sourceID = sourceID
        self.remoteID = remoteID
        self.title = title
        self.author = author
        self.artist = artist
        self.summary = summary
        self.coverURL = coverURL
        self.status = status
        self.rating = rating
        self.categories = categories
        self.lastUpdated = lastUpdated
        self.isFavorite = isFavorite
    }
}

public struct Chapter: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var seriesID: UUID
    public var sourceID: String
    public var remoteID: String
    public var name: String
    public var number: Double
    public var uploadedAt: Date?
    public var pageCount: Int?
    public var isRead: Bool
    public var isBookmarked: Bool

    public init(
        id: UUID = UUID(),
        seriesID: UUID,
        sourceID: String,
        remoteID: String,
        name: String,
        number: Double,
        uploadedAt: Date? = nil,
        pageCount: Int? = nil,
        isRead: Bool = false,
        isBookmarked: Bool = false
    ) {
        self.id = id
        self.seriesID = seriesID
        self.sourceID = sourceID
        self.remoteID = remoteID
        self.name = name
        self.number = number
        self.uploadedAt = uploadedAt
        self.pageCount = pageCount
        self.isRead = isRead
        self.isBookmarked = isBookmarked
    }
}

public struct ReadingProgress: Codable, Equatable, Sendable {
    public var chapterID: UUID
    public var page: Int
    public var scrollOffset: Double
    public var updatedAt: Date

    public init(chapterID: UUID, page: Int = 0, scrollOffset: Double = 0, updatedAt: Date = .now) {
        self.chapterID = chapterID
        self.page = page
        self.scrollOffset = scrollOffset
        self.updatedAt = updatedAt
    }
}
