import XCTest
@testable import ReaCore

final class ZipArchiveTests: XCTestCase {
    // MARK: - Fixture builder

    /// Builds a ZIP in memory with explicit field offsets, so the fixture can
    /// never drift from the spec the reader implements.
    ///
    /// Local file header (30 bytes + name + extra):
    ///   0 sig, 4 version, 6 flags, 8 method, 10 modTime, 12 modDate,
    ///   14 crc, 18 compressed, 22 uncompressed, 26 nameLen, 28 extraLen
    ///
    /// Central directory header (46 bytes + name + extra + comment):
    ///   0 sig, 4 versionMadeBy, 6 versionNeeded, 8 flags, 10 method,
    ///   12 modTime, 14 modDate, 16 crc, 20 compressed, 24 uncompressed,
    ///   28 nameLen, 30 extraLen, 32 commentLen, 34 diskStart, 36 intAttrs,
    ///   38 extAttrs, 42 localOffset
    ///
    /// EOCD (22 bytes):
    ///   0 sig, 4 disk, 6 cdDisk, 8 entriesOnDisk, 10 entries,
    ///   12 cdSize, 16 cdOffset, 20 commentLen
    private struct ZipEntry {
        var name: String
        var payload: Data       // stored bytes, or the deflate stream
        var method: UInt16
        var crc: UInt32
        var uncompressedSize: UInt32
    }

    private func makeZip(entries: [ZipEntry]) -> Data {
        var local = Data()
        var central = Data()
        var offsets: [UInt32] = []

        for entry in entries {
            offsets.append(UInt32(local.count))
            let nameBytes = Data(entry.name.utf8)

            // --- local file header ---
            local.append(Self.u32(0x0403_4B50))                 // 0  sig
            local.append(Self.u16(20))                          // 4  version needed
            local.append(Self.u16(0))                           // 6  flags
            local.append(Self.u16(entry.method))                // 8  method
            local.append(Self.u16(0))                           // 10 mod time
            local.append(Self.u16(0x21))                        // 12 mod date
            local.append(Self.u32(entry.crc))                   // 14 crc
            local.append(Self.u32(UInt32(entry.payload.count))) // 18 compressed
            local.append(Self.u32(entry.uncompressedSize))      // 22 uncompressed
            local.append(Self.u16(UInt16(nameBytes.count)))     // 26 name len
            local.append(Self.u16(0))                           // 28 extra len
            local.append(nameBytes)
            local.append(entry.payload)

            // --- central directory header ---
            central.append(Self.u32(0x0201_4B50))               // 0  sig
            central.append(Self.u16(20))                        // 4  version made by
            central.append(Self.u16(20))                        // 6  version needed
            central.append(Self.u16(0))                         // 8  flags
            central.append(Self.u16(entry.method))              // 10 method
            central.append(Self.u16(0))                         // 12 mod time
            central.append(Self.u16(0x21))                      // 14 mod date
            central.append(Self.u32(entry.crc))                 // 16 crc
            central.append(Self.u32(UInt32(entry.payload.count))) // 20 compressed
            central.append(Self.u32(entry.uncompressedSize))    // 24 uncompressed
            central.append(Self.u16(UInt16(nameBytes.count)))   // 28 name len
            central.append(Self.u16(0))                         // 30 extra len
            central.append(Self.u16(0))                         // 32 comment len
            central.append(Self.u16(0))                         // 34 disk start
            central.append(Self.u16(0))                         // 36 internal attrs
            central.append(Self.u32(0))                         // 38 external attrs
            central.append(Self.u32(offsets[offsets.count - 1])) // 42 local offset
            central.append(nameBytes)
        }

        var eocd = Data()
        eocd.append(Self.u32(0x0605_4B50))                      // 0  sig
        eocd.append(Self.u16(0))                                // 4  disk
        eocd.append(Self.u16(0))                                // 6  cd disk
        eocd.append(Self.u16(UInt16(entries.count)))            // 8  entries on disk
        eocd.append(Self.u16(UInt16(entries.count)))            // 10 entries
        eocd.append(Self.u32(UInt32(central.count)))            // 12 cd size
        eocd.append(Self.u32(UInt32(local.count)))              // 16 cd offset
        eocd.append(Self.u16(0))                                // 20 comment len

        return local + central + eocd
    }

    private func storedEntry(_ name: String, _ data: Data) -> ZipEntry {
        ZipEntry(
            name: name,
            payload: data,
            method: 0,
            crc: Self.crc32(data),
            uncompressedSize: UInt32(data.count)
        )
    }

    private func storedZip(_ files: [(String, Data)]) -> Data {
        makeZip(entries: files.map { storedEntry($0.0, $0.1) })
    }

    private static func u16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func u32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - Tests

    func testReadsStoredEntries() throws {
        let payloadA = Data("page one".utf8)
        let payloadB = Data("page two".utf8)
        let zip = storedZip([("001.jpg", payloadA), ("002.jpg", payloadB)])

        let archive = try ZipArchive(data: zip)
        XCTAssertEqual(archive.entries.count, 2)
        XCTAssertEqual(try archive.data(forName: "001.jpg"), payloadA)
        XCTAssertEqual(try archive.data(forName: "002.jpg"), payloadB)
    }

    func testImageEntriesSortedNaturally() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let zip = storedZip([
            ("page10.png", png),
            ("page2.png", png),
            ("page1.png", png),
            ("notes.txt", Data("skip".utf8))
        ])
        let archive = try ZipArchive(data: zip)
        let names = archive.imageEntries().map(\.name)
        XCTAssertEqual(names, ["page1.png", "page2.png", "page10.png"])
    }

    func testRejectsNonZip() {
        XCTAssertThrowsError(try ZipArchive(data: Data("not a zip".utf8)))
    }

    func testCBZReaderServesPages() throws {
        let payload = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let zip = storedZip([("001.jpg", payload)])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).cbz")
        try zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try CBZReader(url: url)
        XCTAssertEqual(try reader.pageCount(), 1)
        XCTAssertEqual(try reader.pageData(at: 0), payload)
    }

    /// Hand-built fixed-Huffman DEFLATE stream for "hello hello hello hello",
    /// so decompression is covered without a compressor in the test target.
    private static let deflatedHelloHello = Data([
        0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xC8, 0x40, 0x27, 0x01
    ])
    private static let helloHelloText = Data("hello hello hello hello".utf8)

    func testInflatesRawDeflateEntry() throws {
        let entry = ZipEntry(
            name: "001.jpg",
            payload: Self.deflatedHelloHello,
            method: 8,
            crc: Self.crc32(Self.helloHelloText),
            uncompressedSize: UInt32(Self.helloHelloText.count)
        )
        let archive = try ZipArchive(data: makeZip(entries: [entry]))
        let parsed = try XCTUnwrap(archive.entries.first)
        XCTAssertEqual(parsed.compression, 8)
        XCTAssertEqual(try archive.extract(parsed), Self.helloHelloText)
    }

    func testInflateRoundTripsKnownStream() throws {
        let inflated = try Inflate.raw(
            Self.deflatedHelloHello,
            expectedSize: Self.helloHelloText.count
        )
        XCTAssertEqual(inflated, Self.helloHelloText)
    }

    func testTruncatedEntryThrows() throws {
        var zip = storedZip([("001.jpg", Data("page one".utf8))])
        zip.removeLast(zip.count - 40)   // keep the header, drop the directory
        XCTAssertThrowsError(try ZipArchive(data: zip))
    }
}
