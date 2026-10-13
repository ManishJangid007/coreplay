import Foundation

/// A container format guessed from a file extension.
///
/// This is only a first, cheap classification. Containers Apple can open are
/// still probed track by track before AVFoundation is chosen; containers Apple
/// cannot open go straight to VLC without probing.
public struct ContainerFormat: Hashable, Sendable {
    public enum Support: Hashable, Sendable {
        /// AVFoundation can open this container. Tracks still need checking.
        case native
        /// Only VLC can open this container.
        case vlcOnly
        /// Unknown extension. Probe, and fall back to VLC if probing fails.
        case unknown
    }

    /// Lowercased extension without the dot, e.g. `"mkv"`. Empty when unknown.
    public let fileExtension: String
    public let support: Support
    public let kindHint: PlaybackItem.Kind

    public init(fileExtension rawExtension: String) {
        let ext = rawExtension.lowercased()
        self.fileExtension = ext
        if let known = ContainerFormat.table[ext] {
            self.support = known.support
            self.kindHint = known.kind
        } else {
            self.support = .unknown
            self.kindHint = .unknown
        }
    }

    public init(url: URL) {
        self.init(fileExtension: url.pathExtension)
    }

    public var isHLSPlaylist: Bool { fileExtension == "m3u8" }

    /// The container's everyday name ("Matroska", "QuickTime"), for Media Info.
    public var displayName: String? {
        ContainerFormat.displayNames[fileExtension]
    }

    private static let displayNames: [String: String] = {
        var names: [String: String] = [:]
        func add(_ extensions: [String], _ name: String) {
            for ext in extensions { names[ext] = name }
        }
        add(["mkv", "mk3d"], "Matroska")
        add(["mka"], "Matroska Audio")
        add(["webm"], "WebM")
        add(["mp4", "m4v"], "MPEG-4")
        add(["m4a", "m4b", "m4p"], "MPEG-4 Audio")
        add(["mov", "qt"], "QuickTime")
        add(["3gp", "3g2"], "3GPP")
        add(["avi", "divx", "xvid"], "AVI")
        add(["ts", "m2ts", "mts", "m2t", "tp", "trp"], "MPEG Transport Stream")
        add(["mpg", "mpeg", "mpe", "vob", "evo"], "MPEG Program Stream")
        add(["ogv", "ogg", "oga", "ogm", "opus", "spx"], "Ogg")
        add(["wmv", "wma", "asf"], "Windows Media")
        add(["flv", "f4v"], "Flash Video")
        add(["rm", "rmvb", "ra"], "RealMedia")
        add(["mxf"], "MXF")
        add(["iso", "img"], "Disc Image")
        add(["mp3"], "MP3")
        add(["flac"], "FLAC")
        add(["wav", "wave", "w64", "rf64"], "WAV")
        add(["aif", "aiff", "aifc"], "AIFF")
        add(["caf"], "Core Audio")
        add(["ape"], "Monkey's Audio")
        add(["wv"], "WavPack")
        add(["dts", "dtshd"], "DTS")
        add(["ac3", "eac3", "ec3"], "Dolby Digital")
        add(["m3u8"], "HTTP Live Streaming")
        return names
    }()

    // MARK: - Table

    private struct Entry {
        let support: Support
        let kind: PlaybackItem.Kind
    }

    private static let table: [String: Entry] = {
        var table: [String: Entry] = [:]
        func add(_ extensions: [String], _ support: Support, _ kind: PlaybackItem.Kind) {
            for ext in extensions { table[ext] = Entry(support: support, kind: kind) }
        }
        // Containers AVFoundation opens natively.
        add(["mp4", "m4v", "mov", "qt", "3gp", "3g2"], .native, .video)
        add(["m4a", "m4b", "m4p", "mp3", "aac", "adts", "wav", "wave", "aif", "aiff", "aifc",
             "caf", "flac", "ac3", "eac3", "ec3", "amr"], .native, .audio)
        add(["m3u8"], .native, .video)
        // Containers only VLC opens.
        add(["mkv", "mk3d", "webm", "avi", "divx", "xvid", "wmv", "asf", "flv", "f4v", "ogv",
             "ts", "m2ts", "mts", "m2t", "tp", "trp", "vob", "mpg", "mpeg", "mpe", "m1v", "m2v",
             "mpv", "dv", "rm", "rmvb", "nsv", "nut", "mxf", "gxf", "wtv", "dvr-ms", "evo",
             "ogm", "iso", "img", "bin", "h264", "h265", "hevc", "264", "265", "y4m", "ivf"],
            .vlcOnly, .video)
        add(["mka", "ogg", "oga", "opus", "spx", "wma", "ape", "wv", "mpc", "tta", "tak",
             "dts", "dtshd", "thd", "mlp", "mp2", "mp1", "mpa", "dsf", "dff", "au", "snd",
             "voc", "w64", "rf64", "mod", "xm", "s3m", "it", "mtm", "669", "ra", "awb",
             "mid", "midi", "kar", "shn", "ofr", "ofs"],
            .vlcOnly, .audio)
        return table
    }()
}
