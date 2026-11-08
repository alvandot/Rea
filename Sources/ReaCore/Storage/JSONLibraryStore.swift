import Foundation

/// Atomic JSON-file library store. Zero dependencies; used as the default on
/// non-Apple platforms and as the fallback if Core Data fails to load.
public actor JSONLibraryStore: LibraryStore {
    private struct Snapshot: Codable {
        var series: [Series] = []
        var chapters: [Chapter] = []
        var progress: [UUID: ReadingProgress] = [:]
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("library.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Series

    public func loadSeries() async throws -> [Series] {
        try snapshot().series
    }

    public func upsert(_ series: [Series]) async throws {
        var snap = try snapshot()
        var byID = Dictionary(uniqueKeysWithValues: snap.series.map { ($0.id, $0) })
        for item in series { byID[item.id] = item }
        snap.series = Array(byID.values)
        try persist(snap)
    }

    public func delete(seriesID: UUID) async throws {
        var snap = try snapshot()
        snap.series.removeAll { $0.id == seriesID }
        let removed = snap.chapters.filter { $0.seriesID == seriesID }.map(\.id)
        snap.chapters.removeAll { $0.seriesID == seriesID }
        for id in removed { snap.progress[id] = nil }
        try persist(snap)
    }

    // MARK: - Chapters

    public func chapters(for seriesID: UUID) async throws -> [Chapter] {
        try snapshot().chapters
            .filter { $0.seriesID == seriesID }
            .sorted { $0.number < $1.number }
    }

    public func replaceChapters(for seriesID: UUID, with chapters: [Chapter]) async throws {
        var snap = try snapshot()
        // Preserve read/bookmark flags across a refresh, matched by remote id.
        let previous = snap.chapters.filter { $0.seriesID == seriesID }
        var readState: [String: (Bool, Bool)] = [:]
        for chapter in previous {
            readState[chapter.remoteID] = (chapter.isRead, chapter.isBookmarked)
        }
        let staleIDs = previous.map(\.id)
        var incoming = chapters
        for index in incoming.indices {
            if let flags = readState[incoming[index].remoteID] {
                incoming[index].isRead = flags.0
                incoming[index].isBookmarked = flags.1
            }
        }
        snap.chapters.removeAll { $0.seriesID == seriesID }
        snap.chapters.append(contentsOf: incoming)
        // Drop progress rows for chapters that no longer exist.
        let liveIDs = Set(incoming.map(\.id))
        for id in staleIDs where !liveIDs.contains(id) { snap.progress[id] = nil }
        try persist(snap)
    }

    public func setChapterRead(_ chapterID: UUID, read: Bool) async throws {
        var snap = try snapshot()
        guard let idx = snap.chapters.firstIndex(where: { $0.id == chapterID }) else { return }
        snap.chapters[idx].isRead = read
        try persist(snap)
    }

    // MARK: - Progress

    public func progress(for chapterID: UUID) async throws -> ReadingProgress? {
        try snapshot().progress[chapterID]
    }

    public func saveProgress(_ progress: ReadingProgress) async throws {
        var snap = try snapshot()
        if let existing = snap.progress[progress.chapterID], existing.updatedAt > progress.updatedAt {
            return   // last-write-wins
        }
        snap.progress[progress.chapterID] = progress
        try persist(snap)
    }

    // MARK: - Disk

    private func snapshot() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Snapshot() }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty { return Snapshot() }
        return try decoder.decode(Snapshot.self, from: data)
    }

    private func persist(_ snapshot: Snapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
