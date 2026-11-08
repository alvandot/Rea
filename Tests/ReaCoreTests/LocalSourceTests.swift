import XCTest
@testable import ReaCore

final class LocalSourceTests: XCTestCase {
    private var root: URL!
    private var files: LocalFileStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaLocal-\(UUID().uuidString)", isDirectory: true)
        files = LocalFileStore(root: root)
        try files.ensureDirectories()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writePNG(to url: URL) throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try data.write(to: url)
    }

    func testListsAdoptedFiles() async throws {
        let source = root.appendingPathComponent("Series One.cbz")
        try Data([0x50, 0x4B, 0x03, 0x04]).write(to: source)

        let name = try files.adopt(source)
        XCTAssertEqual(name, "Series One.cbz")

        let local = LocalSource(files: files)
        let all = try await local.popular(page: 1)
        XCTAssertEqual(all.items.count, 1)
        XCTAssertEqual(all.items[0].title, "Series One")
    }

    func testImageFolderProducesPages() async throws {
        let folder = root.appendingPathComponent("Folder Series", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writePNG(to: folder.appendingPathComponent("page-2.png"))
        try writePNG(to: folder.appendingPathComponent("page-1.png"))

        let local = LocalSource(files: files)
        let chapters = try await local.chapters(seriesRemoteID: "Folder Series")
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].pageCount, 2)

        let pages = try await local.pages(chapterRemoteID: "Folder Series#main")
        XCTAssertEqual(pages.count, 2)
        guard case .localFile(let first) = pages[0].origin else {
            return XCTFail("Expected local file origin")
        }
        XCTAssertEqual(first.lastPathComponent, "page-1.png")
    }

    func testSearchFiltersByTitle() async throws {
        for name in ["Alpha.cbz", "Beta.cbz"] {
            try Data([0x50, 0x4B, 0x03, 0x04]).write(to: root.appendingPathComponent(name))
        }
        let local = LocalSource(files: files)
        let found = try await local.search("alp", page: 1)
        XCTAssertEqual(found.items.map(\.title), ["Alpha"])
    }
}
