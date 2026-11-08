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

        var output = Data(count: max(expectedSize, 1024))
        var input = [UInt8](data)

        let result: Data? = input.withUnsafeMutableBufferPointer { inBuf in
            output.withUnsafeMutableBytes { outBuf -> Data? in
                stream.next_in = inBuf.baseAddress
                stream.avail_in = uInt(inBuf.count)
                stream.next_out = outBuf.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outBuf.count)

                status = inflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END else { return nil }
                let written = outBuf.count - Int(stream.avail_out)
                return output.prefix(written)
            }
        }
        guard let result else { throw ZipError.truncated }
        return result
    }
    #endif
}
