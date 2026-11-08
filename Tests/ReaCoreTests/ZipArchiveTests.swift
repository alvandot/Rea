import XCTest
@testable import ReaCore

final class ZipArchiveTests: XCTestCase {
    /// Builds a minimal stored-only ZIP in memory so the reader can be tested
    /// without fixtures.
    private func makeZip(files: [(name: String, data: Data)]) -> Data {
        var local = Data()
        var central = Data()
        var offsets: [Int] = []

        for file in files {
            offsets.append(local.count)
            let nameBytes = Data(file.name.utf8)
            let crc = Self.crc32(file.data).littleEndian
            let size = UInt32(file.data.count).littleEndian

            local.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])
            local.append(contentsOf: [20, 0].map { UInt8($0) })       // version
            local.append(contentsOf: [0, 0].map { UInt8($0) })        // flags
            local.append(contentsOf: [0, 0].map { UInt8($0) })        // method = stored
            local.append(contentsOf: [0, 0, 0, 0].map { UInt8($0) })  // time/date
            withUnsafeBytes(of: crc) { local.append(contentsOf: $0) }
            withUnsafeBytes(of: size) { local.append(contentsOf: $0) }
            withUnsafeBytes(of: size) { local.append(contentsOf: $0) }
            local.append(contentsOf: [UInt8(nameBytes.count), 0])
            local.append(contentsOf: [0, 0])                           // extra len
            local.append(nameBytes)
            local.append(file.data)

            central.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
            central.append(contentsOf: [20, 0].map { UInt8($0) })
            central.append(contentsOf: [20, 0].map { UInt8($0) })
            central.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
            withUnsafeBytes(of: crc) { central.append(contentsOf: $0) }
            withUnsafeBytes(of: size) { central.append(contentsOf: $0) }
            withUnsafeBytes(of: size) { central.append(contentsOf: $0) }
            central.append(contentsOf: [UInt8(nameBytes.count), 0])
            central.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
            withUnsafeBytes(of: UInt32(offsets.last!).littleEndian) { central.append(contentsOf: $0) }
            central.append(nameBytes)
        }

        let centralOffset = UInt32(local.count).littleEndian
        let centralSize = UInt32(central.count).littleEndian
        let count = UInt16(files.count).littleEndian

        var eocd = Data([0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0])
        withUnsafeBytes(of: count) { eocd.append(contentsOf: $0) }
        withUnsafeBytes(of: count) { eocd.append(contentsOf: $0) }
        withUnsafeBytes(of: centralSize) { eocd.append(contentsOf: $0) }
        withUnsafeBytes(of: centralOffset) { eocd.append(contentsOf: $0) }
        eocd.append(contentsOf: [0, 0])

        return local + central + eocd
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

    func testReadsStoredEntries() throws {
        let payloadA = Data("page one".utf8)
        let payloadB = Data("page two".utf8)
        let zip = makeZip(files: [("001.jpg", payloadA), ("002.jpg", payloadB)])

        let archive = try ZipArchive(data: zip)
        XCTAssertEqual(archive.entries.count, 2)
        XCTAssertEqual(try archive.data(forName: "001.jpg"), payloadA)
        XCTAssertEqual(try archive.data(forName: "002.jpg"), payloadB)
    }

    func testImageEntriesSortedNaturally() throws {
        let zip = makeZip(files: [
            ("page10.png", Data([0x89, 0x50, 0x4E, 0x47])),
            ("page2.png", Data([0x89, 0x50, 0x4E, 0x47])),
            ("page1.png", Data([0x89, 0x50, 0x4E, 0x47])),
            ("notes.txt", Data("skip".utf8))
        ])
        let archive = try ZipArchive(data: zip)
        let names = archive.imageEntries().map(\.name)
        XCTAssertEqual(names, ["page1.png", "page2.png", "page10.png"])
    }

    func testRejectsNonZip() {
        XCTAssertThrowsError(try ZipArchive(data: Data("not a zip".utf8)))
    }

    /// Builds a ZIP whose single entry uses compression method 8 (raw DEFLATE).
    /// The payload is pre-compressed by the caller because the test target has
    /// no compressor; `storedPayload` is the expanded bytes.
    private func makeDeflatedZip(name: String, deflated: Data, uncompressedSize: UInt32) -> Data {
        let nameBytes = Data(name.utf8)
        var local = Data()

        local.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])
        local.append(contentsOf: [20, 0].map { UInt8($0) })
        local.append(contentsOf: [0, 0].map { UInt8($0) })
        local.append(contentsOf: [8, 0].map { UInt8($0) })        // method = deflate
        local.append(contentsOf: [0, 0, 0, 0].map { UInt8($0) })
        local.append(contentsOf: [0, 0, 0, 0].map { UInt8($0) })  // crc (unchecked)
        withUnsafeBytes(of: UInt32(deflated.count).littleEndian) { local.append(contentsOf: $0) }
        withUnsafeBytes(of: uncompressedSize.littleEndian) { local.append(contentsOf: $0) }
        local.append(contentsOf: [UInt8(nameBytes.count), 0])
        local.append(contentsOf: [0, 0])
        local.append(nameBytes)
        local.append(deflated)

        var central = Data([0x50, 0x4b, 0x01, 0x02])
        central.append(contentsOf: [20, 0].map { UInt8($0) })
        central.append(contentsOf: [20, 0].map { UInt8($0) })
        central.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
        central.append(contentsOf: [0, 0, 0, 0].map { UInt8($0) })
        withUnsafeBytes(of: UInt32(deflated.count).littleEndian) { central.append(contentsOf: $0) }
        withUnsafeBytes(of: uncompressedSize.littleEndian) { central.append(contentsOf: $0) }
        central.append(contentsOf: [UInt8(nameBytes.count), 0])
        central.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
        central.append(contentsOf: [0, 0, 0, 0])
        central.append(nameBytes)

        var eocd = Data([0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0])
        withUnsafeBytes(of: UInt16(1).littleEndian) { eocd.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1).littleEndian) { eocd.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(central.count).littleEndian) { eocd.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(local.count).littleEndian) { eocd.append(contentsOf: $0) }
        eocd.append(contentsOf: [0, 0])

        return local + central + eocd
    }

    /// Hand-built fixed-Huffman deflate stream so the test does not depend on
    /// a compressor being available in the test target.
    func testInflatesRawDeflateEntry() throws {
        let original = Data("hello hello hello hello".utf8)
        let deflated = Data([
            0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xC8, 0x40, 0x27, 0x01
        ])
        let zip = makeDeflatedZip(
            name: "001.jpg",
            deflated: deflated,
            uncompressedSize: UInt32(original.count)
        )

        let archive = try ZipArchive(data: zip)
        guard let entry = archive.entries.first else {
            return XCTFail("no entries parsed")
        }
        XCTAssertEqual(entry.compression, 8)
        XCTAssertEqual(try archive.extract(entry), original)
    }

    func testInflateRoundTripsWithCompressionApi() throws {
        // Independent check of Inflate itself against a known deflate stream.
        let original = Data("hello hello hello hello".utf8)
        let deflated = Data([
            0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xC8, 0x40, 0x27, 0x01
        ])
        let inflated = try Inflate.raw(deflated, expectedSize: original.count)
        XCTAssertEqual(inflated, original)
    }

    func testCBZReaderServesPages() throws {
        let payload = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let zip = makeZip(files: [("001.jpg", payload)])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).cbz")
        try zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try CBZReader(url: url)
        XCTAssertEqual(try reader.pageCount(), 1)
        XCTAssertEqual(try reader.pageData(at: 0), payload)
    }
}
