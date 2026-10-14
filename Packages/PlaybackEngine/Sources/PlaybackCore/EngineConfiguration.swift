import Foundation

/// User-controlled engine settings, mapped to libVLC options and router overrides.
public struct EngineConfiguration: Hashable, Sendable {
    /// Route every item to VLC, even when AVFoundation could play it.
    public var alwaysUseVLC: Bool
    /// Use VideoToolbox hardware decoding in VLC when available.
    public var hardwareDecoding: Bool
    /// How much network data VLC buffers before playing, in milliseconds.
    public var networkCachingMilliseconds: Int
    /// Extra libVLC command-line options, e.g. `--deinterlace=1 --audio-time-stretch`.
    public var customLibVLCOptions: String
    /// How plain-text subtitles look (VLC's text renderer reads it at start-up).
    public var subtitleStyle: SubtitleStyle
    /// The character set of subtitle files that aren't Unicode (an iconv
    /// name), or `nil` to let VLC decide.
    public var subtitleEncoding: String?

    public init(
        alwaysUseVLC: Bool = false,
        hardwareDecoding: Bool = true,
        networkCachingMilliseconds: Int = 1_000,
        customLibVLCOptions: String = "",
        subtitleStyle: SubtitleStyle = .standard,
        subtitleEncoding: String? = nil
    ) {
        self.alwaysUseVLC = alwaysUseVLC
        self.hardwareDecoding = hardwareDecoding
        self.networkCachingMilliseconds = networkCachingMilliseconds
        self.customLibVLCOptions = customLibVLCOptions
        self.subtitleStyle = subtitleStyle
        self.subtitleEncoding = subtitleEncoding
    }

    /// Options used to create the shared `VLCLibrary`. Changing these takes
    /// effect for the next VLC engine that's created.
    public var libVLCLibraryOptions: [String] {
        var options = [
            // VLCKit's macOS defaults include --play-and-pause; we want end of
            // media to stop so the queue can advance the same way on every platform.
            "--no-play-and-pause",
            "--network-caching=\(max(0, networkCachingMilliseconds))",
        ]
        #if os(macOS)
        // VLCKit's macOS default is "macosx": an NSOpenGLView VLC draws into
        // from its own thread. Inside SwiftUI's layer-backed views that fails
        // an OpenGL assertion (fatal in VLCKit's development builds) when the
        // view is resized as a video starts, e.g. while the player slides in.
        // The Core Animation layer output draws on the main thread, in step
        // with layout.
        options.append("--vout=caopengllayer")
        #endif
        options += subtitleStyle.libVLCOptions
        // Custom options come last, so they win.
        options += EngineConfiguration.parseOptions(customLibVLCOptions)
            .filter { $0.hasPrefix("--") }
        return options
    }

    /// Options added to every `VLCMedia` before it plays.
    public var libVLCMediaOptions: [String] {
        var options: [String] = []
        if !hardwareDecoding {
            // Prefer FFmpeg's software decoder (no hwaccel); keep the other
            // decoders as a fallback for codecs avcodec can't handle.
            options.append(":codec=avcodec,all")
            options.append(":avcodec-hw=none")
        }
        if let subtitleEncoding, !subtitleEncoding.isEmpty {
            options.append(":subsdec-encoding=\(subtitleEncoding)")
        }
        options += EngineConfiguration.parseOptions(customLibVLCOptions)
            .filter { $0.hasPrefix(":") }
        return options
    }

    /// Splits a command line the way a shell would: whitespace separates
    /// options, quotes group, and backslashes escape the next character.
    public static func parseOptions(_ commandLine: String) -> [String] {
        var options: [String] = []
        var current = ""
        var hasToken = false
        var quote: Character?
        var escaping = false

        for character in commandLine {
            if escaping {
                current.append(character)
                hasToken = true
                escaping = false
                continue
            }
            if character == "\\" {
                escaping = true
                continue
            }
            if let open = quote {
                if character == open {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                hasToken = true
                continue
            }
            if character.isWhitespace {
                if hasToken {
                    options.append(current)
                    current = ""
                    hasToken = false
                }
                continue
            }
            current.append(character)
            hasToken = true
        }
        if hasToken {
            options.append(current)
        }
        return options
    }
}
