import XCTest
@testable import ReaCore

private struct FixedTokenProvider: TokenProvider {
    let token: String?
    func accessToken() async throws -> String? { token }
    func refresh() async throws -> String? { token }
}

private struct RecordingTransport: HTTPTransport {
    let payload: Data
    let status: Int
    let recorder: Recorder

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await recorder.record(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (payload, response)
    }
}

private actor Recorder {
    private(set) var requests: [URLRequest] = []
    func record(_ request: URLRequest) { requests.append(request) }
}

final class TrackingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaTrack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testLinkStoreRoundTrip() async throws {
        let store = JSONTrackerLinkStore(directory: root)
        let link = TrackerLink(seriesID: UUID(), trackerID: "anilist", remoteID: "42")
        try await store.save(link)
        let loaded = try await store.link(for: link.seriesID, trackerID: "anilist")
        XCTAssertEqual(loaded?.remoteID, "42")

        try await store.remove(seriesID: link.seriesID, trackerID: "anilist")
        let removed = try await store.link(for: link.seriesID, trackerID: "anilist")
        XCTAssertNil(removed)
    }

    func testSyncProgressUpdatesLastSynced() async throws {
        let store = JSONTrackerLinkStore(directory: root)
        let seriesID = UUID()
        let tracker = MyAnimeListTracker(tokens: FixedTokenProvider(token: "abc"))
        let manager = TrackingManager(links: store)
        await manager.register(tracker)
        try await manager.link(seriesID: seriesID, trackerID: "myanimelist", remoteID: "7")

        // No network is reached: updateProgress will fail, and the manager must
        // report it without throwing or corrupting progress.
        let report = await manager.syncProgress(seriesID: seriesID, chaptersRead: 3, status: .reading)
        XCTAssertTrue(report.pushed.isEmpty)
        XCTAssertNotNil(report.failureSummary)

        let link = try await store.link(for: seriesID, trackerID: "myanimelist")
        XCTAssertEqual(link?.lastSyncedProgress, 0)
    }

    func testSkipWhenProgressNotAhead() async throws {
        let store = JSONTrackerLinkStore(directory: root)
        let seriesID = UUID()
        let manager = TrackingManager(links: store)
        await manager.register(MyAnimeListTracker(tokens: FixedTokenProvider(token: "abc")))
        var link = TrackerLink(seriesID: seriesID, trackerID: "myanimelist", remoteID: "7")
        link.lastSyncedProgress = 10
        try await store.save(link)

        let report = await manager.syncProgress(seriesID: seriesID, chaptersRead: 5, status: nil)
        XCTAssertTrue(report.isEmpty)
    }

    func testAniListUpdateSendsGraphQL() async throws {
        let payload = Data(#"{"data":{"SaveMediaListEntry":{"mediaId":9,"progress":4,"status":"CURRENT"}}}"#.utf8)
        let recorder = Recorder()
        let transport = RecordingTransport(payload: payload, status: 200, recorder: recorder)
        let tracker = AniListTracker(tokens: FixedTokenProvider(token: "tok"), transport: transport)

        let entry = try await tracker.updateProgress(remoteID: "9", chapters: 4, status: .reading)
        XCTAssertEqual(entry.progress, 4)
        XCTAssertEqual(entry.status, .reading)

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func testMALUpdateSendsPATCH() async throws {
        let payload = Data(#"{"status":"reading","num_chapters_read":12}"#.utf8)
        let recorder = Recorder()
        let transport = RecordingTransport(payload: payload, status: 200, recorder: recorder)
        let tracker = MyAnimeListTracker(tokens: FixedTokenProvider(token: "tok"), transport: transport)

        let entry = try await tracker.updateProgress(remoteID: "5", chapters: 12, status: .reading)
        XCTAssertEqual(entry.progress, 12)

        let requests = await recorder.requests
        XCTAssertEqual(requests.first?.httpMethod, "PATCH")
    }
}
