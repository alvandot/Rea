import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Deterministic identity for remote objects: the same `sourceID + remoteID`
/// always yields the same local `UUID`, so re-fetching doesn't fork records.
public enum StableID {
    public static func uuid(sourceID: String, remoteID: String) -> UUID {
        uuid(from: "\(sourceID)\u{0}\(remoteID)")
    }

    public static func uuid(from string: String) -> UUID {
        var bytes = digest(Data(string.utf8))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func digest(_ data: Data) -> [UInt8] {
        #if canImport(CryptoKit)
        return Array(SHA256.hash(data: data).prefix(16))
        #else
        var state: UInt64 = 0xcbf29ce484222325
        var out = [UInt8](repeating: 0, count: 16)
        for (i, byte) in data.enumerated() {
            state = (state ^ UInt64(byte)) &* 0x100000001b3
            out[i % 16] ^= UInt8(truncatingIfNeeded: state >> ((i % 8) * 8))
        }
        return out
        #endif
    }
}
