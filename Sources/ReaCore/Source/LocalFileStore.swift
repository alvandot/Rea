import Foundation

/// Keeps user-imported comic files under the app's own storage so they stay
/// readable without security-scoped bookmarks.
public struct LocalFileStore: Sendable {
    public let root: URL
    public let pageCache: URL

    public init(root: URL) {
        self.root = root
        self.pageCache = root.appendingPathComponent("pages", isDirectory: true)
    }

    public static var `default`: LocalFileStore {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return LocalFileStore(root: base.appendingPathComponent("Rea/Local", isDirectory: true))
    }

    public func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pageCache, withIntermediateDirectories: true)
    }

    /// Copies an imported file/folder into managed storage and returns the
    /// stable name used as the series `remoteID`.
    @discardableResult
    public func adopt(_ sourceURL: URL, preferredName: String? = nil) throws -> String {
        try ensureDirectories()
        let name = preferredName ?? sourceURL.lastPathComponent
        let destination = uniqueDestination(for: name)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination.lastPathComponent
    }

    public func url(for name: String) -> URL { root.appendingPathComponent(name) }

    public func contains(name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    public func remove(name: String) throws {
        let file = url(for: name)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        let cache = pageCache.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: cache.path) {
            try FileManager.default.removeItem(at: cache)
        }
    }

    private func uniqueDestination(for name: String) -> URL {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var candidate = root.appendingPathComponent(name)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = ext.isEmpty ? "" : ".\(ext)"
            candidate = root.appendingPathComponent("\(stem)-\(counter)\(suffix)")
            counter += 1
        }
        return candidate
    }
}
