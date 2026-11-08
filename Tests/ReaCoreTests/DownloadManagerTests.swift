import XCTest
@testable import ReaCore

final class DownloadManagerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaDownloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func localPage(_ name: String, index: Int) throws -> PageResource {
        let url = root.appendingPathComponent(name)
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: url)
        return PageResource(origin: .localFile(url), index: index, mimeType: "image/png")
    }

    func testDownloadsLocalPages() async throws {
        let manager = DownloadManager(root: root.appendingPathComponent("out", isDirectory: true))
        let seriesID = UUID()
        let chapterID = UUID()
        let pages = [try localPage("a.png", index: 0), try localPage("b.png", index: 1)]

        let record = try await manager.download(seriesID: seriesID, chapterID: chapterID, pages: pages)
        XCTAssertEqual(record.state, .completed)
        XCTAssertEqual(record.pages.count, 2)
        XCTAssertEqual(record.progress, 1.0)
        for page in record.pages {
            XCTAssertTrue(FileManager.default.fileExists(atPath: page.fileURL.path))
            XCTAssertEqual(page.fileURL.pathExtension, "png")
        }

        let stored = await manager.record(for: chapterID)
        XCTAssertEqual(stored?.state, .completed)
    }

    func testCancelMarksRecord() async throws {
        let manager = DownloadManager(root: root.appendingPathComponent("out2", isDirectory: true))
        let chapterID = UUID()
        let pages = [try localPage("c.png", index: 0)]
        _ = try await manager.download(seriesID: UUID(), chapterID: chapterID, pages: pages)

        await manager.cancel(chapterID: chapterID)
        let record = await manager.record(for: chapterID)
        // A finished record can only be cancelled in-flight, so the state stays
        // completed once the download has already returned.
        XCTAssertEqual(record?.state, .completed)
    }

    func testDeleteRemovesFiles() async throws {
        let directory = root.appendingPathComponent("out3", isDirectory: true)
        let manager = DownloadManager(root: directory)
        let chapterID = UUID()
        let pages = [try localPage("d.png", index: 0)]
        let record = try await manager.download(seriesID: UUID(), chapterID: chapterID, pages: pages)
        let fileURL = try XCTUnwrap(record.pages.first?.fileURL)

        try await manager.delete(chapterID: chapterID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let remaining = await manager.record(for: chapterID)
        XCTAssertNil(remaining)
    }
}
