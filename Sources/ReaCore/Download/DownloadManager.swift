import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// State of a single chapter download.
public enum DownloadState: String, Codable, Sendable, Equatable {
    case queued
    case downloading
    case completed
    case failed
    case cancelled
}

/// A downloaded page on disk.
public struct DownloadedPage: Codable, Hashable, Sendable {
    public let index: Int
    public let fileURL: URL

    public init(index: Int, fileURL: URL) {
        self.index = index
        self.fileURL = fileURL
    }
}

public struct DownloadRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let seriesID: UUID
    public let chapterID: UUID
    public var state: DownloadState
    public var progress: Double
    public var pages: [DownloadedPage]
    public var savedAt: Date?

    public init(
        id: UUID = UUID(),
        seriesID: UUID,
        chapterID: UUID,
        state: DownloadState = .queued,
        progress: Double = 0,
        pages: [DownloadedPage] = [],
        savedAt: Date? = nil
    ) {
        self.id = id
        self.seriesID = seriesID
        self.chapterID = chapterID
        self.state = state
        self.progress = progress
        self.pages = pages
        self.savedAt = savedAt
    }
}

public enum DownloadError: Error, Equatable, Sendable {
    case failedPage(Int)
    case unsupportedOrigin
    case storageFailed
}

/// Downloads chapter pages into a local cache and reports progress through an
/// `AsyncStream` of records.
public actor DownloadManager {
    private let root: URL
    private let session: URLSession
    private var records: [UUID: DownloadRecord] = [:]
    private var continuation: AsyncStream<DownloadRecord>.Continuation?

    public init(root: URL, session: URLSession = .shared) {
        self.root = root
        self.session = session
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Starts (or returns) the state feed for all downloads.
    public func stateFeed() -> AsyncStream<DownloadRecord> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    public func record(for chapterID: UUID) -> DownloadRecord? {
        records.values.first { $0.chapterID == chapterID }
    }

    public func allRecords() -> [DownloadRecord] {
        Array(records.values)
    }

    /// Downloads every page of a chapter. Returns the final record.
    @discardableResult
    public func download(
        seriesID: UUID,
        chapterID: UUID,
        pages: [PageResource]
    ) async throws -> DownloadRecord {
        var record = DownloadRecord(seriesID: seriesID, chapterID: chapterID, state: .downloading)
        records[record.id] = record
        emit(record)

        let directory = root.appendingPathComponent(chapterID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var downloaded: [DownloadedPage] = []
        for page in pages {
            do {
                let data: Data
                switch page.origin {
                case .remote(let url):
                    let (payload, response) = try await session.data(from: url)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw DownloadError.failedPage(page.index)
                    }
                    data = payload
                case .localFile(let url):
                    data = try Data(contentsOf: url, options: .mappedIfSafe)
                }

                let fileURL = directory.appendingPathComponent("page-\(page.index).\(Self.extensionFor(page, data: data))")
                try data.write(to: fileURL, options: .atomic)
                downloaded.append(DownloadedPage(index: page.index, fileURL: fileURL))

                record.pages = downloaded
                record.progress = pages.isEmpty ? 1 : Double(downloaded.count) / Double(pages.count)
                records[record.id] = record
                emit(record)
            } catch {
                record.state = .failed
                records[record.id] = record
                emit(record)
                throw DownloadError.failedPage(page.index)
            }
        }

        record.state = .completed
        record.progress = 1
        record.savedAt = .now
        records[record.id] = record
        emit(record)
        return record
    }

    public func cancel(chapterID: UUID) {
        guard let record = records.values.first(where: { $0.chapterID == chapterID }) else { return }
        var cancelled = record
        cancelled.state = .cancelled
        records[record.id] = cancelled
        emit(cancelled)
    }

    public func delete(chapterID: UUID) throws {
        guard let record = records.values.first(where: { $0.chapterID == chapterID }) else { return }
        let directory = root.appendingPathComponent(chapterID.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        records[record.id] = nil
    }

    private func emit(_ record: DownloadRecord) {
        continuation?.yield(record)
    }

    private static func extensionFor(_ page: PageResource, data: Data) -> String {
        if let mime = page.mimeType {
            if mime.contains("png") { return "png" }
            if mime.contains("jpeg") || mime.contains("jpg") { return "jpg" }
            if mime.contains("webp") { return "webp" }
            if mime.contains("gif") { return "gif" }
        }
        guard data.count >= 4 else { return "jpg" }
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "jpg"
    }
}
