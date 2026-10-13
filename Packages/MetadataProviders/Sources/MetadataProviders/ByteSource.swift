import Foundation

/// Random-access bytes: a file on disk, or data in memory for tests.
///
/// Tag readers only ever read the small regions they need (headers, tag
/// blocks, the last few kilobytes), so scanning never loads whole media files.
public protocol ByteSource: Sendable {
    var size: Int64 { get }
    /// Up to `count` bytes starting at `offset`; fewer at the end of the source.
    func read(at offset: Int64, count: Int) throws -> Data
}

public extension ByteSource {
    func bytes(at offset: Int64, count: Int) throws -> [UInt8] {
        [UInt8](try read(at: offset, count: count))
    }
}

/// A file opened for reading. Reads are serialised, so one source can be
/// shared by the readers that look at different parts of the same file.
public final class FileByteSource: ByteSource, @unchecked Sendable {
    public let size: Int64
    private let handle: FileHandle
    private let lock = NSLock()

    public init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        size = Int64(try handle.seekToEnd())
    }

    deinit {
        try? handle.close()
    }

    public func read(at offset: Int64, count: Int) throws -> Data {
        guard offset >= 0, count > 0, offset < size else { return Data() }
        let available = Int(min(Int64(count), size - offset))
        lock.lock()
        defer { lock.unlock() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: available) ?? Data()
    }
}

/// Bytes already in memory.
public struct DataByteSource: ByteSource {
    public let data: Data

    public init(_ data: Data) {
        self.data = data
    }

    public init(_ bytes: [UInt8]) {
        self.data = Data(bytes)
    }

    public var size: Int64 { Int64(data.count) }

    public func read(at offset: Int64, count: Int) throws -> Data {
        guard offset >= 0, count > 0, offset < size else { return Data() }
        let start = data.startIndex + Int(offset)
        let end = min(start + count, data.endIndex)
        return Data(data[start..<end])
    }
}

/// A cursor over a byte array that never traps: reads past the end throw.
struct ByteReader {
    struct OutOfBounds: Error {}

    let bytes: [UInt8]
    var offset: Int

    init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    var remaining: Int { max(0, bytes.count - offset) }
    var isAtEnd: Bool { offset >= bytes.count }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, count <= remaining else { throw OutOfBounds() }
        offset += count
    }

    mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw OutOfBounds() }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func u16be() throws -> UInt16 {
        let value = try Bytes.u16be(bytes, offset)
        offset += 2
        return value
    }

    mutating func u16le() throws -> UInt16 {
        let value = try Bytes.u16le(bytes, offset)
        offset += 2
        return value
    }

    mutating func u32be() throws -> UInt32 {
        let value = try Bytes.u32be(bytes, offset)
        offset += 4
        return value
    }

    mutating func u32le() throws -> UInt32 {
        let value = try Bytes.u32le(bytes, offset)
        offset += 4
        return value
    }

    mutating func u64be() throws -> UInt64 {
        let value = try Bytes.u64be(bytes, offset)
        offset += 8
        return value
    }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= remaining else { throw OutOfBounds() }
        defer { offset += count }
        return bytes[offset..<(offset + count)]
    }
}

/// Fixed-width integer reads at an index, bounds-checked.
enum Bytes {
    static func check(_ bytes: [UInt8], _ index: Int, _ width: Int) throws {
        guard index >= 0, index + width <= bytes.count else { throw ByteReader.OutOfBounds() }
    }

    static func u16be(_ bytes: [UInt8], _ i: Int) throws -> UInt16 {
        try check(bytes, i, 2)
        return UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
    }

    static func u16le(_ bytes: [UInt8], _ i: Int) throws -> UInt16 {
        try check(bytes, i, 2)
        return UInt16(bytes[i + 1]) << 8 | UInt16(bytes[i])
    }

    static func u24be(_ bytes: [UInt8], _ i: Int) throws -> UInt32 {
        try check(bytes, i, 3)
        return UInt32(bytes[i]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2])
    }

    static func u32be(_ bytes: [UInt8], _ i: Int) throws -> UInt32 {
        try check(bytes, i, 4)
        return UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])
    }

    static func u32le(_ bytes: [UInt8], _ i: Int) throws -> UInt32 {
        try check(bytes, i, 4)
        return UInt32(bytes[i + 3]) << 24 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i])
    }

    static func u64be(_ bytes: [UInt8], _ i: Int) throws -> UInt64 {
        UInt64(try u32be(bytes, i)) << 32 | UInt64(try u32be(bytes, i + 4))
    }

    static func u64le(_ bytes: [UInt8], _ i: Int) throws -> UInt64 {
        UInt64(try u32le(bytes, i + 4)) << 32 | UInt64(try u32le(bytes, i))
    }

    /// A 28-bit "syncsafe" integer (ID3v2): 7 bits per byte.
    static func syncsafe(_ bytes: [UInt8], _ i: Int) throws -> Int {
        try check(bytes, i, 4)
        return Int(bytes[i] & 0x7F) << 21 | Int(bytes[i + 1] & 0x7F) << 14 | Int(bytes[i + 2] & 0x7F) << 7 | Int(bytes[i + 3] & 0x7F)
    }

    static func ascii(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: Unicode.ASCII.self)
    }

    /// Four-character codes may contain © (0xA9), so decode as Latin-1.
    static func fourCC(_ bytes: [UInt8], _ i: Int) -> String? {
        guard i >= 0, i + 4 <= bytes.count else { return nil }
        return Text.latin1(bytes[i..<(i + 4)])
    }

    static func matches(_ bytes: [UInt8], _ i: Int, _ pattern: String) -> Bool {
        let pattern = Array(pattern.utf8)
        guard i >= 0, i + pattern.count <= bytes.count else { return false }
        return Array(bytes[i..<(i + pattern.count)]) == pattern
    }
}
