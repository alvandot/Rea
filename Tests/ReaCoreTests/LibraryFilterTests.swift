import XCTest
@testable import ReaCore

final class LibraryFilterTests: XCTestCase {
    private func series(_ title: String, status: ReadingStatus, favorite: Bool = false) -> Series {
        Series(
            id: StableID.uuid(sourceID: "t", remoteID: title),
            sourceID: "t",
            remoteID: title,
            title: title,
            status: status,
            isFavorite: favorite
        )
    }

    func testScopeFiltersByStatus() {
        let items = [
            series("A", status: .reading),
            series("B", status: .completed),
            series("C", status: .planToRead)
        ]
        let filter = LibraryFilter(scope: .reading)
        XCTAssertEqual(filter.apply(to: items).map(\.title), ["A"])
    }

    func testFavoritesScope() {
        let items = [
            series("A", status: .reading, favorite: true),
            series("B", status: .reading, favorite: false)
        ]
        XCTAssertEqual(LibraryFilter(scope: .favorites).apply(to: items).map(\.title), ["A"])
    }

    func testQueryMatchesTitleAuthorCategory() {
        var item = Series(
            id: StableID.uuid(sourceID: "t", remoteID: "x"),
            sourceID: "t",
            remoteID: "x",
            title: "Blue Sky",
            author: "Rin",
            categories: ["Drama"]
        )
        item.categories = ["Drama"]
        let items = [item]
        XCTAssertEqual(LibraryFilter(query: "blue").apply(to: items).count, 1)
        XCTAssertEqual(LibraryFilter(query: "rin").apply(to: items).count, 1)
        XCTAssertEqual(LibraryFilter(query: "drama").apply(to: items).count, 1)
        XCTAssertEqual(LibraryFilter(query: "zzz").apply(to: items).count, 0)
    }

    func testIsActive() {
        let filter = LibraryFilter()
        XCTAssertFalse(filter.isActive)
        var changed = filter
        changed.scope = .reading
        XCTAssertTrue(changed.isActive)
    }
}
