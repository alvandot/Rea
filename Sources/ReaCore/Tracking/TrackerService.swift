import Foundation

public enum TrackerStatus: String, Codable, CaseIterable, Sendable {
    case watching, reading, completed, onHold, dropped, planToRead

    public var displayName: String {
        switch self {
        case .watching: return "Watching"
        case .reading: return "Reading"
        case .completed: return "Completed"
        case .onHold: return "On Hold"
        case .dropped: return "Dropped"
        case .planToRead: return "Plan to Read"
        }
    }
}

public struct TrackerSearchResult: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var totalChapters: Int?
    public var coverURL: URL?

    public init(id: String, title: String, totalChapters: Int? = nil, coverURL: URL? = nil) {
        self.id = id
        self.title = title
        self.totalChapters = totalChapters
        self.coverURL = coverURL
    }
}

public struct TrackerEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public var remoteID: String
    public var title: String
    public var progress: Int
    public var status: TrackerStatus

    public init(id: String, remoteID: String, title: String, progress: Int, status: TrackerStatus) {
        self.id = id
        self.remoteID = remoteID
        self.title = title
        self.progress = progress
        self.status = status
    }
}

public enum TrackerError: Error, Equatable, Sendable {
    case notAuthenticated
    case unauthorized
    case notFound
    case network(String)
    case parse(String)
    case unsupported
}

/// Supplies the current bearer token; the app layer owns the OAuth dance.
public protocol TokenProvider: Sendable {
    func accessToken() async throws -> String?
    func refresh() async throws -> String?
}

/// A remote list tracker (MyAnimeList, AniList, …).
public protocol TrackerService: Sendable {
    var id: String { get }
    var name: String { get }
    var isAuthenticated: Bool { get async }

    func search(_ query: String) async throws -> [TrackerSearchResult]
    func list(status: TrackerStatus?) async throws -> [TrackerEntry]
    func updateProgress(remoteID: String, chapters: Int, status: TrackerStatus?) async throws -> TrackerEntry
    func deleteEntry(remoteID: String) async throws
}

/// A stored link between a local series and a tracker media entry.
public struct TrackerLink: Codable, Hashable, Sendable, Identifiable {
    public var seriesID: UUID
    public var trackerID: String
    public var remoteID: String
    public var lastSyncedProgress: Int
    public var lastSyncedAt: Date?

    public var id: String { "\(trackerID):\(seriesID.uuidString)" }

    public init(
        seriesID: UUID,
        trackerID: String,
        remoteID: String,
        lastSyncedProgress: Int = 0,
        lastSyncedAt: Date? = nil
    ) {
        self.seriesID = seriesID
        self.trackerID = trackerID
        self.remoteID = remoteID
        self.lastSyncedProgress = lastSyncedProgress
        self.lastSyncedAt = lastSyncedAt
    }
}

public protocol TrackerLinkStore: Sendable {
    func allLinks() async throws -> [TrackerLink]
    func link(for seriesID: UUID, trackerID: String) async throws -> TrackerLink?
    func save(_ link: TrackerLink) async throws
    func remove(seriesID: UUID, trackerID: String) async throws
}

public actor JSONTrackerLinkStore: TrackerLinkStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("tracker-links.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func allLinks() async throws -> [TrackerLink] {
        try load()
    }

    public func link(for seriesID: UUID, trackerID: String) async throws -> TrackerLink? {
        try load().first { $0.seriesID == seriesID && $0.trackerID == trackerID }
    }

    public func save(_ link: TrackerLink) async throws {
        var links = try load()
        links.removeAll { $0.seriesID == link.seriesID && $0.trackerID == link.trackerID }
        links.append(link)
        try persist(links)
    }

    public func remove(seriesID: UUID, trackerID: String) async throws {
        var links = try load()
        links.removeAll { $0.seriesID == seriesID && $0.trackerID == trackerID }
        try persist(links)
    }

    private func load() throws -> [TrackerLink] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty { return [] }
        return try decoder.decode([TrackerLink].self, from: data)
    }

    private func persist(_ links: [TrackerLink]) throws {
        try encoder.encode(links).write(to: fileURL, options: .atomic)
    }
}
