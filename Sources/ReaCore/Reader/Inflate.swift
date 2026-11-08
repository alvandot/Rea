import Foundation
#if canImport(Compression)
import Compression
#elseif canImport(zlib)
import zlib
#endif

/// Raw-DEFLATE decompressor for ZIP entries.
///
/// `zlib` is the module name on Linux; on Apple platforms the same C API lives
/// in the SDK's `zlib.h` with no importable module, which is why the Apple path
/// talks to `Compression.framework` instead.
public enum Inflate {
    /// Decompresses a raw deflate stream (no zlib header).
    public static func raw(_ data: Data, expectedSize: Int) throws -> Data {
        guard !data.isEmpty else { return Data() }

        #if canImport(Compression)
        return try compressionInflate(data, expectedSize: expectedSize)
        #elseif canImport(zlib)
        return try zlibInflate(data, expectedSize: expectedSize)
        #else
        // Without a decompressor only stored (uncompressed) entries can be read;
        // the ZIP layer handles those directly and never calls this path.
        throw ZipError.unsupportedCompression(8)
        #endif
    }
}

#if canImport(Compression)
extension Inflate {
    /// Raw DEFLATE via `COMPRESSION_ZLIB`, which on Apple platforms means
    /// "zlib algorithm, raw stream" — exactly the payload of a ZIP entry with
    /// compression method 8.
    private static func compressionInflate(_ data: Data, expectedSize: Int) throws -> Data {
        let capacity = max(expectedSize, data.count * 4, 1024)
        var output = Data(count: capacity)

        let written: Int = output.withUnsafeMutableBytes { outBuf in
            guard let outBase = outBuf.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { inBuf -> Int in
                guard let inBase = inBuf.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    outBase,
                    outBuf.count,
                    inBase,
                    inBuf.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard written > 0 else { throw ZipError.truncated }
        guard written < capacity else {
            // Buffer was exactly filled: the stream may have been truncated to
            // fit. Retry once with room to spare so a full-page image is never
            // silently clipped.
            return try compressionInflate(data, expectedSize: capacity * 2)
        }
        return output.prefix(written)
    }
}
#endif

#if !canImport(Compression) && canImport(zlib)
extension Inflate {
    private static func zlibInflate(_ data: Data, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else { throw ZipError.truncated }
        defer { inflateEnd(&stream) }

        var output = Data(count: max(expectedSize, 1024))
        var input = [UInt8](data)
        var status: Int32 = Z_OK

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
}
#endif
