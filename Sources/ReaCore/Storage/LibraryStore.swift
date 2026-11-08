import Foundation

/// Persistence contract for the library. Two backends ship: atomic JSON and
/// Core Data (optionally CloudKit-backed).
public protocol LibraryStore: Sendable {
    func loadSeries() async throws -> [Series]
    func upsert(_ series: [Series]) async throws
    func delete(seriesID: UUID) async throws

    func chapters(for seriesID: UUID) async throws -> [Chapter]
    func replaceChapters(for seriesID: UUID, with chapters: [Chapter]) async throws
    func setChapterRead(_ chapterID: UUID, read: Bool) async throws

    func progress(for chapterID: UUID) async throws -> ReadingProgress?
    func saveProgress(_ progress: ReadingProgress) async throws
}
