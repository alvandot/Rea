import Foundation

/// Exposes files adopted by `LocalFileStore` as `ContentSource` entries.
public struct LocalSource: ContentSource {
    public nonisolated let id = "local"
    public nonisolated let name = "Local Files"
    public nonisolated let language = "und"

    private let files: LocalFileStore

    public init(files: LocalFileStore = .default) {
        self.files = files
    }

    // MARK: - ContentSource

    public func popular(page: Int) async throws -> PagedResult<Series> {
        paginate(try await allSeries(), page: page)
    }

    public func latest(page: Int) async throws -> PagedResult<Series> {
        paginate(try await allSeries(), page: page)
    }

    public func search(_ query: String, page: Int) async throws -> PagedResult<Series> {
        let all = try await allSeries()
        let filtered = query.isEmpty
            ? all
            : all.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return paginate(filtered, page: page)
    }

    public func series(remoteID: String) async throws -> Series {
        let all = try await allSeries()
        guard let match = all.first(where: { $0.remoteID == remoteID }) else { throw SourceError.notFound }
        return match
    }

    public func chapters(seriesRemoteID: String) async throws -> [Chapter] {
        let seriesID = StableID.uuid(sourceID: id, remoteID: seriesRemoteID)
        let pageCount = (try? pageFiles(for: seriesRemoteID).count) ?? 0
        return [
            Chapter(
                id: StableID.uuid(sourceID: id, remoteID: "\(seriesRemoteID)#main"),
                seriesID: seriesID,
                sourceID: id,
                remoteID: "\(seriesRemoteID)#main",
                name: "Full",
                number: 1,
                pageCount: pageCount
            )
        ]
    }

    public func pages(chapterRemoteID: String) async throws -> [PageResource] {
        guard let name = chapterRemoteID.split(separator: "#").first.map(String.init) else {
            throw SourceError.notFound
        }
        let urls = try pageFiles(for: name)
        return urls.enumerated().map { index, url in
            PageResource(origin: .localFile(url), index: index, mimeType: Self.mimeType(for: url))
        }
    }

    // MARK: - Listing

    private func paginate(_ items: [Series], page: Int) -> PagedResult<Series> {
        let limit = 40
        let offset = max(0, (page - 1) * limit)
        let slice = items.dropFirst(offset).prefix(limit)
        return PagedResult(items: Array(slice), hasNext: offset + slice.count < items.count)
    }

    private func allSeries() async throws -> [Series] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: files.root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.lastPathComponent != "pages" }
            .map { url in
                Series(
                    id: StableID.uuid(sourceID: id, remoteID: url.lastPathComponent),
                    sourceID: id,
                    remoteID: url.lastPathComponent,
                    title: url.deletingPathExtension().lastPathComponent,
                    status: .reading
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Pages

    private func pageFiles(for name: String) throws -> [URL] {
        let source = files.url(for: name)
        guard FileManager.default.fileExists(atPath: source.path) else { throw SourceError.notFound }
        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        if isDirectory {
            return try ImageFolderReader(folder: source).imageURLs()
        }

        let cacheDir = files.pageCache.appendingPathComponent(name, isDirectory: true)
        let manifest = cacheDir.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifest),
           let names = try? JSONDecoder().decode([String].self, from: data),
           !names.isEmpty,
           names.allSatisfy({ FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent($0).path) }) {
            return names.map { cacheDir.appendingPathComponent($0) }
        }

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let reader = try LocalDocument.reader(for: source)
        let count = try reader.pageCount()
        var names: [String] = []
        for index in 0..<count {
            let data = try reader.pageData(at: index)
            let pageName = String(format: "page-%04d.%@", index, Self.extensionFor(data, source: source))
            try data.write(to: cacheDir.appendingPathComponent(pageName), options: .atomic)
            names.append(pageName)
        }
        try JSONEncoder().encode(names).write(to: manifest, options: .atomic)
        return names.map { cacheDir.appendingPathComponent($0) }
    }

    private static func extensionFor(_ data: Data, source: URL) -> String {
        if let sniffed = sniffImageExtension(data) { return sniffed }
        let sourceExt = source.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(sourceExt) { return sourceExt }
        return "png"
    }

    private static func sniffImageExtension(_ data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if bytes[0..<4].elementsEqual([0x52, 0x49, 0x46, 0x46]),
           bytes[8..<12].elementsEqual([0x57, 0x45, 0x42, 0x50]) { return "webp" }
        return nil
    }

    private static func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return nil
        }
    }
}
