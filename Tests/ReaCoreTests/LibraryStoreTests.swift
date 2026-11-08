import XCTest
@testable import ReaCore

final class LibraryStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() -> JSONLibraryStore {
        JSONLibraryStore(directory: root)
    }

    private func sampleSeries() -> Series {
        Series(
            id: StableID.uuid(sourceID: "test", remoteID: "series-a"),
            sourceID: "test",
            remoteID: "series-a",
            title: "Sample",
            author: "Someone"
        )
    }

    func testUpsertAndLoad() async throws {
        let store = makeStore()
        let series = sampleSeries()
        try await store.upsert([series])
        let loaded = try await store.loadSeries()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "Sample")
    }

    func testChapterFlagsSurviveRefresh() async throws {
        let store = makeStore()
        let series = sampleSeries()
        try await store.upsert([series])

        var chapter = Chapter(
            id: StableID.uuid(sourceID: "test", remoteID: "ch-1"),
            seriesID: series.id,
            sourceID: "test",
            remoteID: "ch-1",
            name: "Chapter 1",
            number: 1
        )
        chapter.isRead = true
        chapter.isBookmarked = true
        try await store.replaceChapters(for: series.id, with: [chapter])

        // Refresh with the same remote id but default flags.
        var refreshed = chapter
        refreshed.isRead = false
        refreshed.isBookmarked = false
        try await store.replaceChapters(for: series.id, with: [refreshed])

        let stored = try await store.chapters(for: series.id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertTrue(stored[0].isRead)
        XCTAssertTrue(stored[0].isBookmarked)
    }

    func testProgressLastWriteWins() async throws {
        let store = makeStore()
        let series = sampleSeries()
        try await store.upsert([series])
        let chapterID = StableID.uuid(sourceID: "test", remoteID: "ch-1")

        let newer = ReadingProgress(chapterID: chapterID, page: 5, updatedAt: Date())
        let older = ReadingProgress(chapterID: chapterID, page: 1, updatedAt: Date().addingTimeInterval(-60))
        try await store.saveProgress(newer)
        try await store.saveProgress(older)

        let loaded = try await store.progress(for: chapterID)
        XCTAssertEqual(loaded?.page, 5)
    }

    func testDeleteRemovesChaptersAndProgress() async throws {
        let store = makeStore()
        let series = sampleSeries()
        try await store.upsert([series])
        let chapter = Chapter(
            id: StableID.uuid(sourceID: "test", remoteID: "ch-1"),
            seriesID: series.id,
            sourceID: "test",
            remoteID: "ch-1",
            name: "Chapter 1",
            number: 1
        )
        try await store.replaceChapters(for: series.id, with: [chapter])
        try await store.saveProgress(ReadingProgress(chapterID: chapter.id, page: 3))

        try await store.delete(seriesID: series.id)

        let remainingSeries = try await store.loadSeries()
        let remainingChapters = try await store.chapters(for: series.id)
        let remainingProgress = try await store.progress(for: chapter.id)
        XCTAssertTrue(remainingSeries.isEmpty)
        XCTAssertTrue(remainingChapters.isEmpty)
        XCTAssertNil(remainingProgress)
    }
}
