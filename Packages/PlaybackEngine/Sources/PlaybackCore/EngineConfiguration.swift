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

    public init(
        alwaysUseVLC: Bool = false,
        hardwareDecoding: Bool = true,
        networkCachingMilliseconds: Int = 1_000,
        customLibVLCOptions: String = ""
    ) {
        self.alwaysUseVLC = alwaysUseVLC
        self.hardwareDecoding = hardwareDecoding
        self.networkCachingMilliseconds = networkCachingMilliseconds
        self.customLibVLCOptions = customLibVLCOptions
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
