import Foundation

/// The kinds of video disc Coreplay plays (with VLC, menus included).
public enum DiscKind: String, Hashable, Sendable, Codable, CaseIterable {
    case dvd
    case bluray

    public var title: String {
        switch self {
        case .dvd: "DVD"
        case .bluray: "Blu-ray"
        }
    }
}

/// A DVD or Blu-ray: a folder copied from the disc (the one holding VIDEO_TS
/// or BDMV) or an image of it (`.iso`).
public struct Disc: Hashable, Sendable {
    public var kind: DiscKind
    /// The folder that holds VIDEO_TS or BDMV, or the image: what the
    /// library lists as one video.
    public var root: URL
    /// What VLC opens. A DVD's VIDEO_TS folder rather than the one around
    /// it, since that may be all the sandbox lets Coreplay read (when you
    /// open VIDEO_TS itself); libdvdread finds the disc from either.
    public var playbackURL: URL
    public var isImage: Bool
    /// An image's volume name ("HEAT_DISC1"), when it has a readable one.
    public var volumeName: String?

    public init(kind: DiscKind, root: URL, playbackURL: URL? = nil, isImage: Bool, volumeName: String? = nil) {
        self.kind = kind
        self.root = root
        self.playbackURL = playbackURL ?? root
        self.isImage = isImage
        self.volumeName = volumeName
    }

    /// What to call it before the library knows better: the folder's or
    /// image's name ("Heat (1995)"), or the volume's when that's all there is.
    public var displayName: String {
        let name = isImage ? root.deletingPathExtension().lastPathComponent : root.lastPathComponent
        if !name.isEmpty, name != "/" {
            return name
        }
        return volumeName.map(Self.readableVolumeName) ?? kind.title
    }

    /// "HEAT_DISC_1" → "Heat Disc 1".
    public static func readableVolumeName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in word.prefix(1).uppercased() + word.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

extension PlaybackItem {
    /// The item as the disc it turned out to be: VLC opens the disc, and the
    /// disc's name replaces one made from a VIDEO_TS or IFO path.
    public func playing(_ disc: Disc) -> PlaybackItem {
        var item = self
        if libraryID == nil, title == PlaybackItem.displayTitle(for: url) {
            item.title = disc.displayName
        }
        item.url = disc.playbackURL
        item.disc = disc.kind
        item.kind = .video
        return item
    }
}

/// Finds discs: folders copied from DVDs and Blu-rays, and disc images.
public enum DiscLayout {
    /// Folders that make up a disc and never hold media of their own. The
    /// library treats the folder around them as one video.
    public static let structureFolders: Set<String> = ["VIDEO_TS", "AUDIO_TS", "BDMV", "CERTIFICATE", "AACS", "BDSVM"]

    /// Extensions of disc images.
    public static let imageExtensions: Set<String> = ["iso", "img"]

    /// Whether the VLC engine can play discs. The official VLCKit 4.0.0a25
    /// binary is built without libdvdnav, libdvdread and libbluray (its
    /// configure line has --disable-dvdnav, --disable-dvdread and
    /// --disable-bluray), so DVD and Blu-ray folders and images can't play:
    /// the player says so, and the library lists a disc's VOB and M2TS files
    /// as it always did. Everything here is ready for a VLCKit with them.
    public static let canPlayDiscs = false

    /// The disc at `url`: a folder holding VIDEO_TS or BDMV, one of those
    /// folders, an IFO file inside VIDEO_TS, or an image of a DVD or Blu-ray.
    /// `nil` for anything else, images of other discs included.
    public static func disc(at url: URL) -> Disc? {
        guard url.isFileURL else { return nil }
        let fileExtension = url.pathExtension.lowercased()
        if imageExtensions.contains(fileExtension) {
            guard let image = DiscImage.inspect(fileAt: url) else { return nil }
            return Disc(kind: image.kind, root: url, isImage: true, volumeName: image.volumeName)
        }
        if fileExtension == "ifo" || fileExtension == "bup" {
            // VIDEO_TS.IFO opened by itself: the DVD it belongs to, as VLC does.
            let folder = url.deletingLastPathComponent()
            guard folder.lastPathComponent.uppercased() == "VIDEO_TS" else { return nil }
            return folderDisc(folder)
        }
        if ContainerFormat(fileExtension: fileExtension).support != .unknown {
            return nil // a media file (and no folder is named like one)
        }
        guard isDirectory(url) else { return nil }
        return folderDisc(url)
    }

    /// `false` when `url` can't be a disc (a media file, or not a file at
    /// all), without touching the disk.
    public static func mightBeDisc(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let fileExtension = url.pathExtension.lowercased()
        return imageExtensions.contains(fileExtension) || fileExtension == "ifo" || fileExtension == "bup"
            || ContainerFormat(fileExtension: fileExtension).support == .unknown
    }

    /// What kind of disc a folder holds (VIDEO_TS or BDMV inside it), if any.
    public static func kind(ofFolderAt folder: URL) -> DiscKind? {
        let contents = entries(of: folder)
        if let videoTS = contents["VIDEO_TS"], entries(of: videoTS)["VIDEO_TS.IFO"] != nil {
            return .dvd
        }
        if let bdmv = contents["BDMV"], entries(of: bdmv)["INDEX.BDMV"] != nil {
            return .bluray
        }
        return nil
    }

    /// The disc a folder is part of: the folder itself, or its VIDEO_TS or BDMV.
    private static func folderDisc(_ folder: URL) -> Disc? {
        let name = folder.lastPathComponent.uppercased()
        if name == "VIDEO_TS", entries(of: folder)["VIDEO_TS.IFO"] != nil {
            return Disc(kind: .dvd, root: folder.deletingLastPathComponent(), playbackURL: folder, isImage: false)
        }
        if name == "BDMV", entries(of: folder)["INDEX.BDMV"] != nil {
            return Disc(kind: .bluray, root: folder.deletingLastPathComponent(), isImage: false)
        }
        let contents = entries(of: folder)
        if let videoTS = contents["VIDEO_TS"], entries(of: videoTS)["VIDEO_TS.IFO"] != nil {
            return Disc(kind: .dvd, root: folder, playbackURL: videoTS, isImage: false)
        }
        if let bdmv = contents["BDMV"], entries(of: bdmv)["INDEX.BDMV"] != nil {
            return Disc(kind: .bluray, root: folder, isImage: false)
        }
        return nil
    }

    /// Upper-cased name → entry, so discs copied to case-sensitive disks
    /// ("video_ts") are found too.
    public static func entries(of folder: URL) -> [String: URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return [:] }
        var result: [String: URL] = [:]
        for name in names where !name.hasPrefix(".") {
            result[name.uppercased()] = folder.appending(path: name)
        }
        return result
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// The files in a disc's VIDEO_TS (by upper-case name), for `DVDVideoInfo`:
    /// from the folder, or from inside the image.
    public static func videoTSFiles(of disc: Disc) -> ((String) -> Data?)? {
        guard disc.kind == .dvd else { return nil }
        if disc.isImage {
            guard let image = try? DiscImage(url: disc.root), let folder = image.iso9660Folder(named: "VIDEO_TS") else { return nil }
            return { name in
                folder[name].flatMap { image.read(extent: $0, limit: DVDVideoInfo.maximumIFOSize) }
            }
        }
        let files = entries(of: disc.playbackURL)
        return { name in
            guard let url = files[name.uppercased()],
                  let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                  size <= DVDVideoInfo.maximumIFOSize else { return nil }
            return try? Data(contentsOf: url)
        }
    }
}

/// Reads what a disc image holds without mounting it: ISO 9660 (DVDs carry
/// it beside UDF), or UDF alone (Blu-ray).
struct DiscImage {
    static let sectorSize = 2_048

    /// Where a file is inside the image.
    struct Extent: Hashable {
        var sector: Int
        var size: Int
    }

    private let handle: FileHandle
    let fileSize: Int

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        fileSize = Int((try? handle.seekToEnd()) ?? 0)
    }

    func read(offset: Int, count: Int) -> Data? {
        guard offset >= 0, count > 0, offset < fileSize else { return nil }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: min(count, fileSize - offset))
        } catch {
            return nil
        }
    }

    func read(extent: Extent, limit: Int) -> Data? {
        guard extent.size > 0, extent.size <= limit else { return nil }
        return read(offset: extent.sector * Self.sectorSize, count: extent.size)
    }

    /// The kind of video disc an image holds, and its volume name.
    static func inspect(fileAt url: URL) -> (kind: DiscKind, volumeName: String?)? {
        guard let image = try? DiscImage(url: url) else { return nil }
        let descriptors = image.volumeDescriptors()
        var volumeName: String?
        if let primary = descriptors.primary {
            volumeName = Self.text(primary, from: 40, length: 32)
            if let root = image.rootFolder(primary: primary) {
                if root["VIDEO_TS"] != nil { return (.dvd, volumeName) }
                if root["BDMV"] != nil { return (.bluray, volumeName) }
            }
        }
        // UDF alone (as Blu-ray images are): look for the folder names in
        // the first directories. UDF writes names as a compression byte (8
        // or 16) followed by 8-bit or UTF-16 characters.
        guard descriptors.hasUDF else { return nil }
        // They're near the start; read a few megabytes at a time, so a
        // Blu-ray on a network share is recognised without reading much.
        let chunk = 4 << 20
        var offset = 0
        while offset < min(image.fileSize, 32 << 20) {
            guard let window = image.read(offset: offset, count: chunk + 32) else { break }
            if contains(window, name: "BDMV") { return (.bluray, volumeName) }
            if contains(window, name: "VIDEO_TS") { return (.dvd, volumeName) }
            offset += chunk
        }
        return nil
    }

    /// The ISO 9660 primary volume descriptor, and whether UDF's are there.
    private func volumeDescriptors() -> (primary: Data?, hasUDF: Bool) {
        var primary: Data?
        var hasUDF = false
        for sector in 16..<64 {
            guard let data = read(offset: sector * Self.sectorSize, count: Self.sectorSize), data.count >= 7 else { break }
            let identifier = String(decoding: data[data.startIndex + 1..<data.startIndex + 6], as: UTF8.self)
            switch identifier {
            case "CD001":
                if data[data.startIndex] == 1, primary == nil {
                    primary = data
                }
            case "BEA01", "NSR02", "NSR03", "TEA01":
                hasUDF = hasUDF || identifier.hasPrefix("NSR")
            case "BOOT2", "CDW02":
                continue
            default:
                // The descriptors are over once a sector is none of these.
                if primary != nil || hasUDF {
                    return (primary, hasUDF)
                }
            }
        }
        return (primary, hasUDF)
    }

    /// The root folder's entries (upper-case names, versions dropped).
    private func rootFolder(primary: Data) -> [String: Extent]? {
        guard primary.count >= 190 else { return nil }
        let record = primary.subdata(in: primary.startIndex + 156..<primary.startIndex + 190)
        guard let extent = Self.extent(ofRecord: record) else { return nil }
        return folder(at: extent)
    }

    /// The entries of a folder at the image's top level.
    func iso9660Folder(named name: String) -> [String: Extent]? {
        let descriptors = volumeDescriptors()
        guard let primary = descriptors.primary, let root = rootFolder(primary: primary),
              let extent = root[name.uppercased()] else { return nil }
        return folder(at: extent)
    }

    private func folder(at extent: Extent) -> [String: Extent]? {
        guard extent.size > 0, extent.size <= 1 << 20, let data = read(offset: extent.sector * Self.sectorSize, count: extent.size) else { return nil }
        var entries: [String: Extent] = [:]
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let length = Int(bytes[offset])
            if length == 0 {
                // Records don't cross sectors: the rest of this one is padding.
                offset = (offset / Self.sectorSize + 1) * Self.sectorSize
                continue
            }
            guard length >= 34, offset + length <= bytes.count else { break }
            let nameLength = Int(bytes[offset + 32])
            if nameLength > 0, offset + 33 + nameLength <= offset + length {
                let rawName = bytes[(offset + 33)..<(offset + 33 + nameLength)]
                // "." and ".." are the bytes 0 and 1.
                if !(nameLength == 1 && rawName.first! <= 1) {
                    var name = String(decoding: rawName, as: UTF8.self).uppercased()
                    if let semicolon = name.firstIndex(of: ";") {
                        name = String(name[..<semicolon])
                    }
                    if name.hasSuffix(".") {
                        name.removeLast()
                    }
                    if let entryExtent = Self.extent(ofRecord: Data(bytes[offset..<(offset + length)])) {
                        entries[name] = entryExtent
                    }
                }
            }
            offset += length
        }
        return entries
    }

    /// Where a directory record's data is (both-endian fields; the
    /// little-endian half comes first).
    private static func extent(ofRecord record: Data) -> Extent? {
        guard record.count >= 14 else { return nil }
        let bytes = [UInt8](record)
        let sector = Int(bytes[2]) | Int(bytes[3]) << 8 | Int(bytes[4]) << 16 | Int(bytes[5]) << 24
        let size = Int(bytes[10]) | Int(bytes[11]) << 8 | Int(bytes[12]) << 16 | Int(bytes[13]) << 24
        return Extent(sector: sector, size: size)
    }

    private static func text(_ data: Data, from offset: Int, length: Int) -> String? {
        guard data.count >= offset + length else { return nil }
        let raw = data.subdata(in: data.startIndex + offset..<data.startIndex + offset + length)
        let value = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return value.isEmpty ? nil : value
    }

    /// A UDF file identifier for `name`, in either of its encodings.
    static func contains(_ data: Data, name: String) -> Bool {
        let ascii = Array(name.utf8)
        let narrow = Data([8] + ascii)
        let wide = Data([16] + ascii.flatMap { [0, $0] })
        return data.range(of: narrow) != nil || data.range(of: wide) != nil
    }
}
