import Foundation

/// Pushes reading progress to trackers and keeps link bookkeeping.
public actor TrackingManager {
    private var trackers: [String: any TrackerService] = [:]
    private let links: any TrackerLinkStore

    public init(links: any TrackerLinkStore) {
        self.links = links
    }

    public func register(_ tracker: any TrackerService) { trackers[tracker.id] = tracker }
    public func tracker(id: String) -> (any TrackerService)? { trackers[id] }
    public func allTrackers() -> [any TrackerService] { Array(trackers.values) }

    public func link(seriesID: UUID, trackerID: String, remoteID: String) async throws {
        try await links.save(TrackerLink(seriesID: seriesID, trackerID: trackerID, remoteID: remoteID))
    }

    public func unlink(seriesID: UUID, trackerID: String) async throws {
        try await links.remove(seriesID: seriesID, trackerID: trackerID)
    }

    public func linkFor(seriesID: UUID, trackerID: String) async throws -> TrackerLink? {
        try await links.link(for: seriesID, trackerID: trackerID)
    }

    /// Result of pushing one series to every linked tracker.
    public struct SyncReport: Sendable {
        public var pushed: [String] = []
        public var failures: [String: String] = [:]
        public var isEmpty: Bool { pushed.isEmpty && failures.isEmpty }
        public var pushedCount: Int { pushed.count }

        public var failureSummary: String? {
            guard !failures.isEmpty else { return nil }
            let names = failures.keys.sorted()
            if names.count == 1, let name = names.first, let message = failures[name] {
                return "\(name): \(message)"
            }
            return "\(names.count) trackers failed — \(names.joined(separator: ", "))"
        }
    }

    /// Pushes `chaptersRead` to every linked tracker whose stored progress is
    /// behind. Failures are collected, never thrown, so one bad tracker can't
    /// block the rest.
    @discardableResult
    public func syncProgress(
        seriesID: UUID,
        chaptersRead: Int,
        status: TrackerStatus?
    ) async -> SyncReport {
        var report = SyncReport()
        let all: [TrackerLink]
        do {
            all = try await links.allLinks()
        } catch {
            report.failures["link store"] = error.localizedDescription
            return report
        }

        for link in all where link.seriesID == seriesID {
            guard chaptersRead > link.lastSyncedProgress else { continue }
            guard let tracker = trackers[link.trackerID] else { continue }
            do {
                _ = try await tracker.updateProgress(
                    remoteID: link.remoteID,
                    chapters: chaptersRead,
                    status: status
                )
                var updated = link
                updated.lastSyncedProgress = chaptersRead
                updated.lastSyncedAt = .now
                try await links.save(updated)
                report.pushed.append(link.trackerID)
            } catch {
                // Leave the link untouched so the next sync retries.
                report.failures[link.trackerID] = error.localizedDescription
            }
        }
        return report
    }

    public struct SyncRequest: Sendable {
        public let seriesID: UUID
        public let title: String
        public let chaptersRead: Int
        public let status: TrackerStatus?

        public init(seriesID: UUID, title: String, chaptersRead: Int, status: TrackerStatus?) {
            self.seriesID = seriesID
            self.title = title
            self.chaptersRead = chaptersRead
            self.status = status
        }
    }

    public struct SyncOutcome: Sendable, Identifiable {
        public let seriesID: UUID
        public let title: String
        public let pushed: Int
        public let failure: String?

        public var id: UUID { seriesID }
        public var didPush: Bool { pushed > 0 && failure == nil }
        public var failed: Bool { failure != nil }
    }

    /// Batch sync: yields one outcome per request so a UI can show a live list.
    public func syncAll(_ requests: [SyncRequest]) -> AsyncStream<SyncOutcome> {
        AsyncStream { continuation in
            Task {
                for request in requests {
                    let report = await self.syncProgress(
                        seriesID: request.seriesID,
                        chaptersRead: request.chaptersRead,
                        status: request.status
                    )
                    continuation.yield(SyncOutcome(
                        seriesID: request.seriesID,
                        title: request.title,
                        pushed: report.pushedCount,
                        failure: report.failureSummary
                    ))
                }
                continuation.finish()
            }
        }
    }
}
