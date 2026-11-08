import Foundation
#if canImport(zlib)
import zlib
#endif

/// Raw-DEFLATE decompressor for ZIP entries. Wraps zlib when available and
/// falls back to a stored-only path otherwise.
public enum Inflate {
    /// Decompresses a raw deflate stream (no zlib header).
    public static func raw(_ data: Data, expectedSize: Int) throws -> Data {
        #if canImport(zlib)
        return try zlibInflate(data, expectedSize: expectedSize)
        #else
        // Without zlib only stored (uncompressed) entries can be read; the ZIP
        // layer handles those directly and never calls this path.
        throw ZipError.unsupportedCompression(8)
        #endif
    }

    #if canImport(zlib)
    private static func zlibInflate(_ data: Data, expectedSize: Int) throws -> Data {
        guard !data.isEmpty else { return Data() }
        var stream = z_stream()
        var status = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ZipError.truncated }
        defer { inflateEnd(&stream) }

        // Slack beyond the advertised size: inflate still needs room for the
        // final block marker once the payload fills the buffer exactly.
        var output = Data(count: max(expectedSize, 1024) + 64)
        var input = [UInt8](data)
        var written = 0

        let completed: Bool = input.withUnsafeMutableBufferPointer { inBuf in
            output.withUnsafeMutableBytes { outBuf -> Bool in
                guard let outBase = outBuf.bindMemory(to: Bytef.self).baseAddress else {
                    return false
                }
                stream.next_in = inBuf.baseAddress
                stream.avail_in = uInt(inBuf.count)
                stream.next_out = outBase
                stream.avail_out = uInt(outBuf.count)

                status = inflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END else { return false }
                written = outBuf.count - Int(stream.avail_out)
                return true
            }
        }
        guard completed else { throw ZipError.truncated }
        return output.prefix(written)
    }
    #endif
}
