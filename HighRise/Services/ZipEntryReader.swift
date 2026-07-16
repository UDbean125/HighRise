import Foundation
import Compression

/// Extracts a single named entry from a ZIP container (`.xlsx` and `.docx` are
/// both ZIPs of XML) — a minimal, pure-Swift reader of the ZIP central
/// directory, no third-party dependencies.
///
/// Previously this shelled out to `/usr/bin/unzip`, which is reliable but
/// requires the app to run **unsandboxed** (spawning a subprocess isn't
/// permitted under App Sandbox). Reading the format directly means Office
/// import works the same way in both the unsandboxed Developer ID build and a
/// future sandboxed Mac App Store variant — see `MAS_VARIANT_PLAN.md`.
///
/// Scope: handles the "stored" and "deflate" compression methods (the only
/// two any Office-authoring tool actually emits) and assumes no encryption and
/// no Zip64 — real `.xlsx`/`.docx` files are always small, single-disk, and
/// under 4GB, so none of that machinery is needed here.
enum ZipEntryReader {

    enum ZipError: LocalizedError {
        case entryNotFound(String)
        case malformed(String)
        case unsupportedCompression(UInt16)

        var errorDescription: String? {
            switch self {
            case .entryNotFound(let e):
                return "The file doesn't contain \(e) — it may not be a valid Office document."
            case .malformed(let m):
                return "The file isn't a valid zip archive: \(m)"
            case .unsupportedCompression(let method):
                return "This zip entry uses an unsupported compression method (\(method))."
            }
        }
    }

    /// Returns the raw bytes of `entryName` (e.g. `xl/sharedStrings.xml`)
    /// inside the zip archive at `url`.
    static func entry(_ entryName: String, in url: URL) throws -> Data {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try entry(entryName, in: data)
    }

    /// Same as above, operating on already-loaded archive bytes — the entry
    /// point the unit tests use directly, without needing a file on disk.
    static func entry(_ entryName: String, in data: Data) throws -> Data {
        let record = try centralDirectoryRecord(named: entryName, in: data)
        return try extract(record, from: data)
    }

    // MARK: - Central directory

    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
    private static let centralDirectorySignature: UInt32 = 0x0201_4b50
    private static let localHeaderSignature: UInt32 = 0x0403_4b50

    private struct CentralDirectoryRecord {
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Finds the End Of Central Directory record (always at the very end of
    /// the file, optionally followed only by a comment of up to 65,535 bytes)
    /// and walks the central directory it points to for an entry named
    /// `entryName`.
    private static func centralDirectoryRecord(named entryName: String, in data: Data) throws -> CentralDirectoryRecord {
        guard data.count >= 22 else { throw ZipError.malformed("file too small to be a zip archive") }

        let searchFloor = max(0, data.count - 22 - 65535)
        var eocdOffset: Int?
        var probe = data.count - 22
        while probe >= searchFloor {
            if data.readUInt32(at: probe) == endOfCentralDirectorySignature {
                eocdOffset = probe
                break
            }
            probe -= 1
        }
        guard let eocd = eocdOffset else {
            throw ZipError.malformed("no end-of-central-directory record found")
        }

        let entryCount = Int(data.readUInt16(at: eocd + 10))
        let centralDirectorySize = Int(data.readUInt32(at: eocd + 12))
        let centralDirectoryOffset = Int(data.readUInt32(at: eocd + 16))
        guard centralDirectoryOffset >= 0, centralDirectoryOffset + centralDirectorySize <= data.count else {
            throw ZipError.malformed("central directory extends past the end of the file")
        }

        var offset = centralDirectoryOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, data.readUInt32(at: offset) == centralDirectorySignature else {
                throw ZipError.malformed("corrupt central directory record")
            }
            let compressionMethod = data.readUInt16(at: offset + 10)
            let compressedSize = Int(data.readUInt32(at: offset + 20))
            let uncompressedSize = Int(data.readUInt32(at: offset + 24))
            let nameLength = Int(data.readUInt16(at: offset + 28))
            let extraLength = Int(data.readUInt16(at: offset + 30))
            let commentLength = Int(data.readUInt16(at: offset + 32))
            let localHeaderOffset = Int(data.readUInt32(at: offset + 42))
            let nameStart = offset + 46

            guard let name = data.string(at: nameStart, length: nameLength) else {
                throw ZipError.malformed("unreadable entry name")
            }
            if name == entryName {
                return CentralDirectoryRecord(compressionMethod: compressionMethod,
                                               compressedSize: compressedSize,
                                               uncompressedSize: uncompressedSize,
                                               localHeaderOffset: localHeaderOffset)
            }
            offset = nameStart + nameLength + extraLength + commentLength
        }
        throw ZipError.entryNotFound(entryName)
    }

    /// Reads past the local file header (its name/extra field lengths can
    /// differ from the central directory's) to the entry's compressed bytes,
    /// then decompresses them. Sizes always come from the central directory —
    /// the local header's copies can be zero when a writer used a trailing
    /// data descriptor instead.
    private static func extract(_ record: CentralDirectoryRecord, from data: Data) throws -> Data {
        let localOffset = record.localHeaderOffset
        guard localOffset + 30 <= data.count, data.readUInt32(at: localOffset) == localHeaderSignature else {
            throw ZipError.malformed("corrupt local file header")
        }
        let nameLength = Int(data.readUInt16(at: localOffset + 26))
        let extraLength = Int(data.readUInt16(at: localOffset + 28))
        let dataStart = localOffset + 30 + nameLength + extraLength

        guard dataStart >= 0, dataStart + record.compressedSize <= data.count else {
            throw ZipError.malformed("entry data extends past the end of the file")
        }
        let compressed = data.subdata(in: dataStart..<(dataStart + record.compressedSize))

        switch record.compressionMethod {
        case 0: // stored — already raw bytes
            return compressed
        case 8: // deflate
            return try inflate(compressed, uncompressedSize: record.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(record.compressionMethod)
        }
    }

    /// Inflates raw DEFLATE data (RFC 1951 — no zlib/gzip header or trailer),
    /// which is exactly what ZIP's "deflate" compression method stores.
    /// Apple's Compression framework's `COMPRESSION_ZLIB` algorithm — despite
    /// the name — implements raw DEFLATE, not the zlib container format, so
    /// no header needs to be stripped first.
    private static func inflate(_ compressed: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        var destination = Data(count: uncompressedSize)
        let decodedCount = destination.withUnsafeMutableBytes { destBuffer -> Int in
            compressed.withUnsafeBytes { srcBuffer -> Int in
                guard let destBase = destBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = srcBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destBase, uncompressedSize,
                                                  srcBase, compressed.count,
                                                  nil, COMPRESSION_ZLIB)
            }
        }
        guard decodedCount == uncompressedSize else {
            throw ZipError.malformed("decompression produced \(decodedCount) bytes, expected \(uncompressedSize)")
        }
        return destination
    }
}

private extension Data {
    /// Little-endian reads (the ZIP spec's byte order, matching native
    /// x86/ARM order) directly off the archive's bytes, at an absolute
    /// offset from the start of the (possibly sliced) `Data`.
    func readUInt16(at offset: Int) -> UInt16 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    func string(at offset: Int, length: Int) -> String? {
        guard length >= 0, offset >= 0, offset + length <= count else { return nil }
        return withUnsafeBytes { buffer -> String? in
            guard let base = buffer.baseAddress else { return nil }
            let slice = base.advanced(by: offset)
            return String(bytes: UnsafeRawBufferPointer(start: slice, count: length), encoding: .utf8)
        }
    }
}
