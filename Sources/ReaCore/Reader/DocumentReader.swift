import Foundation

/// A resolved, ordered collection of readable pages from a local file.
public protocol DocumentReader: Sendable {
    static func canOpen(url: URL) -> Bool
    func pageCount() throws -> Int
    func pageData(at index: Int) throws -> Data
}

/// Chooses the correct reader for a local document.
public enum LocalDocument {
    public static func reader(for url: URL) throws -> DocumentReader {
        switch url.pathExtension.lowercased() {
        case "cbz", "zip": return try CBZReader(url: url)
        case "pdf": return try PDFReader(url: url)
        case "cbr":
            throw ZipError.unsupportedCompression(0xffff)   // RAR not supported
        case "jpg", "jpeg", "png", "gif", "webp", "heic":
            return try SingleImageReader(url: url)
        default:
            throw ZipError.unsupportedCompression(0)
        }
    }
}

/// CBZ = ZIP of images.
public struct CBZReader: DocumentReader {
    private let archive: ZipArchive
    private let pages: [ZipArchive.Entry]

    public init(url: URL) throws {
        let archive = try ZipArchive(url: url)
        self.archive = archive
        self.pages = archive.imageEntries()
    }

    public static func canOpen(url: URL) -> Bool {
        ["cbz", "zip"].contains(url.pathExtension.lowercased())
    }

    public func pageCount() throws -> Int { pages.count }

    public func pageData(at index: Int) throws -> Data {
        guard pages.indices.contains(index) else { throw ZipError.truncated }
        return try archive.extract(pages[index])
    }
}

/// Single flat image file.
public struct SingleImageReader: DocumentReader {
    private let data: Data

    public init(url: URL) throws {
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
    }

    public static func canOpen(url: URL) -> Bool {
        ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(url.pathExtension.lowercased())
    }

    public func pageCount() throws -> Int { 1 }

    public func pageData(at index: Int) throws -> Data {
        guard index == 0 else { throw ZipError.truncated }
        return data
    }
}

/// A folder of loose images, sorted naturally.
public struct ImageFolderReader: DocumentReader {
    private let urls: [URL]

    public init(folder: URL) throws {
        let exts = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
        let contents = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        self.urls = contents
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func canOpen(url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    public func pageCount() throws -> Int { urls.count }

    public func pageData(at index: Int) throws -> Data {
        guard urls.indices.contains(index) else { throw ZipError.truncated }
        return try Data(contentsOf: urls[index], options: .mappedIfSafe)
    }

    /// Ordered image URLs (used by `LocalSource` to serve pages directly).
    public func imageURLs() -> [URL] { urls }
}
