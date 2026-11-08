import Foundation

public enum ZipError: Error, Equatable, Sendable {
    case notAZip
    case truncated
    case unsupportedCompression(UInt16)
    case corruptEntry
}

/// Minimal ZIP reader: central directory, stored + deflate entries, ZIP64 sizes.
public struct ZipArchive: Sendable {
    public struct Entry: Hashable, Sendable {
        public let name: String
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let compression: UInt16
        let localHeaderOffset: UInt64
    }

    private let data: Data
    public let entries: [Entry]

    public init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(data: data)
    }

    public init(data: Data) throws {
        self.data = data
        self.entries = try Self.parseCentralDirectory(data)
    }

    // MARK: - Extraction

    public func extract(_ entry: Entry) throws -> Data {
        let offset = Int(entry.localHeaderOffset)
        guard offset + 30 <= data.count else { throw ZipError.truncated }
        // Local file header: sig(4) ver(2) flags(2) method(2) time(2) date(2) crc(4) csize(4) usize(4) nameLen(2) extraLen(2)
        let nameLen = Int(readU16(offset + 26))
        let extraLen = Int(readU16(offset + 28))
        let payloadStart = offset + 30 + nameLen + extraLen
        let size = Int(entry.compressedSize)
        guard payloadStart + size <= data.count else { throw ZipError.truncated }
        let payload = data.subdata(in: payloadStart..<(payloadStart + size))

        switch entry.compression {
        case 0:
            return payload
        case 8:
            return try Inflate.raw(payload, expectedSize: Int(entry.uncompressedSize))
        default:
            throw ZipError.unsupportedCompression(entry.compression)
        }
    }

    public func data(forName name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else { throw ZipError.corruptEntry }
        return try extract(entry)
    }

    /// Image entries in natural (chapter-page) order.
    public func imageEntries() -> [Entry] {
        let exts = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
        return entries
            .filter { !$0.name.hasSuffix("/") && exts.contains(($0.name as NSString).pathExtension.lowercased()) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Parsing

    private static func parseCentralDirectory(_ data: Data) throws -> [Entry] {
        guard let eocd = findEOCD(in: data) else { throw ZipError.notAZip }
        var entryCount = Int(readU16(data, eocd + 10))
        var cdOffset = UInt64(readU32(data, eocd + 16))

        // ZIP64 end-of-central-directory locator sits right before the EOCD.
        if eocd >= 20, readU32(data, eocd - 20) == 0x07064b50 {
            let z64EOCD = UInt64(readU64(data, eocd - 20 + 8))
            guard Int(z64EOCD) + 56 <= data.count else { throw ZipError.truncated }
            entryCount = Int(readU64(data, Int(z64EOCD) + 32))
            cdOffset = readU64(data, Int(z64EOCD) + 48)
        }

        var entries: [Entry] = []
        var cursor = Int(cdOffset)
        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count, readU32(data, cursor) == 0x02014b50 else {
                throw ZipError.corruptEntry
            }
            let compression = readU16(data, cursor + 10)
            var compressedSize = UInt64(readU32(data, cursor + 20))
            var uncompressedSize = UInt64(readU32(data, cursor + 24))
            let nameLen = Int(readU16(data, cursor + 28))
            let extraLen = Int(readU16(data, cursor + 30))
            let commentLen = Int(readU16(data, cursor + 32))
            var localOffset = UInt64(readU32(data, cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLen <= data.count else { throw ZipError.truncated }
            let name = String(decoding: data.subdata(in: nameStart..<(nameStart + nameLen)), as: UTF8.self)

            // ZIP64 extended information: values appear only when the 32-bit
            // field is saturated, in a fixed order.
            if extraLen > 0 {
                let extraStart = nameStart + nameLen
                var e = extraStart
                let extraEnd = extraStart + extraLen
                while e + 4 <= extraEnd {
                    let id = readU16(data, e)
                    let size = Int(readU16(data, e + 2))
                    let body = e + 4
                    if id == 0x0001 {
                        var p = body
                        if uncompressedSize == 0xFFFF_FFFF, p + 8 <= body + size {
                            uncompressedSize = readU64(data, p); p += 8
                        }
                        if compressedSize == 0xFFFF_FFFF, p + 8 <= body + size {
                            compressedSize = readU64(data, p); p += 8
                        }
                        if localOffset == 0xFFFF_FFFF, p + 8 <= body + size {
                            localOffset = readU64(data, p); p += 8
                        }
                    }
                    e = body + size
                }
            }

            entries.append(Entry(
                name: name,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                compression: compression,
                localHeaderOffset: localOffset
            ))
            cursor = nameStart + nameLen + extraLen + commentLen
        }
        return entries
    }

    private static func findEOCD(in data: Data) -> Int? {
        let sig: UInt32 = 0x06054b50
        let minSize = 22
        guard data.count >= minSize else { return nil }
        let lowerBound = max(0, data.count - minSize - 0xFFFF)
        var i = data.count - minSize
        while i >= lowerBound {
            if readU32(data, i) == sig { return i }
            i -= 1
        }
        return nil
    }

    // MARK: - Byte helpers

    private func readU16(_ offset: Int) -> UInt16 { Self.readU16(data, offset) }
    private func readU32(_ offset: Int) -> UInt32 { Self.readU32(data, offset) }

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func readU64(_ data: Data, _ offset: Int) -> UInt64 {
        guard offset + 8 <= data.count else { return 0 }
        var value: UInt64 = 0
        for i in 0..<8 { value |= UInt64(data[offset + i]) << (8 * UInt64(i)) }
        return value
    }
}
