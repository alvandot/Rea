import Foundation
#if canImport(Compression)
import Compression
#elseif canImport(zlib)
import zlib
#endif

/// Raw-DEFLATE decompressor for ZIP entries.
///
/// Apple platforms use `Compression.framework`: the Xcode SDK ships `zlib.h`
/// but no importable `zlib` module, so every `z_stream` symbol is out of scope
/// there. `COMPRESSION_ZLIB` is raw DEFLATE — exactly the payload of a ZIP
/// entry with compression method 8. Linux keeps the zlib C API.
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
    private static func compressionInflate(_ data: Data, expectedSize: Int) throws -> Data {
        // `compression_decode_buffer` returns 0 when the output buffer is too
        // small, so grow the buffer and retry instead of trusting the size
        // recorded in the ZIP directory.
        var capacity = max(expectedSize, 1024)
        for _ in 0..<4 {
            var output = Data(count: capacity)

            let written: Int = output.withUnsafeMutableBytes { outBuf in
                guard let outBase = outBuf.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return data.withUnsafeBytes { inBuf -> Int in
                    guard let inBase = inBuf.bindMemory(to: UInt8.self).baseAddress else {
                        return 0
                    }
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

            if written > 0 {
                return output.prefix(written)
            }
            capacity *= 4
        }
        throw ZipError.truncated
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

        // Slack beyond the advertised size: inflate still needs room for the
        // final block marker once the payload fills the buffer exactly.
        var output = Data(count: max(expectedSize, 1024) + 64)
        var input = [UInt8](data)
        var status: Int32 = Z_OK
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
}
#endif
