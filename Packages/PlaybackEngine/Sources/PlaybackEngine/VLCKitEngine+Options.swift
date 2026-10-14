internal import VLCKit
import Foundation
import PlaybackCore

// Level 2 options for the VLC engine. Every call here was type-checked
// against the VLCKit 4.0.0a25 headers (videoFitMode, videoAspectRatio,
// setCropRatioWithNumerator(_:denominator:), adjustFilter, setDeinterlace,
// audioStereoMode, equalizer, currentSubTitleFontScale, gotoNextFrame,
// gotoPreviousFrame, saveVideoSnapshot(at:withWidth:andHeight:)).
//
// None of them run on the main thread. Each reaches into the running video
// (or audio) output and waits for its lock, and libVLC holds that lock while
// the output is being created, which on macOS and iOS waits for the main
// thread to set up its view. Called from the main thread just as a video
// started, they deadlocked the app: every movie stayed on "loading".

/// The player, carried to `VLCKitEngine.outputQueue`. libVLC is thread-safe,
/// and the VLCKit setters used there are thin wrappers around it.
private struct OutputPlayer: @unchecked Sendable {
    let player: VLCMediaPlayer
}

extension VLCKitEngine {
    /// Runs `work` with the player on the engine's serial output queue.
    func onOutputQueue(_ work: @escaping @Sendable (VLCMediaPlayer) -> Void) {
        let target = OutputPlayer(player: player)
        outputQueue.async {
            work(target.player)
        }
    }

    /// Applies again whatever differs from libVLC's defaults, once the
    /// output exists. Defaults need nothing, so a plain movie touches nothing.
    func applyChosenOptions() {
        if fillMode != .fit { applyFillMode() }
        if aspectRatio != nil { applyAspectRatio() }
        if cropRatio != nil { applyCrop() }
        if !videoAdjustments.isNeutral { applyAdjustments() }
        if deinterlace != .automatic || deinterlaceFilter != .standard { applyDeinterlace() }
        if !viewpoint.isStraightAhead { applyViewpoint() }
        if stereoMode != .automatic { applyStereoMode() }
        if equalizer.isEnabled { applyEqualizer() }
        if subtitleScale != 1 { applySubtitleScale() }
    }

    func applyFillMode() {
        let mode: VLCMediaPlayer.VideoFitMode = fillMode == .fill ? .larger : .smaller
        onOutputQueue { player in
            player.videoFitMode = mode
        }
    }

    func applyAspectRatio() {
        let ratio = aspectRatio?.description
        onOutputQueue { player in
            player.videoAspectRatio = ratio
        }
    }

    func applyCrop() {
        let numerator = UInt32(cropRatio?.width ?? 0)
        let denominator = UInt32(cropRatio?.height ?? 0)
        onOutputQueue { player in
            // 0:0 removes the crop.
            player.setCropRatioWithNumerator(numerator, denominator: denominator)
        }
    }

    func applyAdjustments() {
        let values = videoAdjustments.clamped
        onOutputQueue { player in
            let filter = player.adjustFilter
            if values.isNeutral {
                _ = filter.resetParametersIfNeeded()
                filter.isEnabled = false
                return
            }
            filter.brightness.value = NSNumber(value: values.brightness)
            filter.contrast.value = NSNumber(value: values.contrast)
            filter.saturation.value = NSNumber(value: values.saturation)
            filter.hue.value = NSNumber(value: values.hue)
            filter.gamma.value = NSNumber(value: values.gamma)
            filter.isEnabled = true
        }
    }

    func applyDeinterlace() {
        let mode: VLCDeinterlace = switch deinterlace {
        case .automatic: .auto
        case .on: .on
        case .off: .off
        }
        let filter = deinterlaceFilter.rawValue
        onOutputQueue { player in
            player.setDeinterlace(mode, withFilter: filter)
        }
    }

    /// Where a 360° video looks. libVLC keeps the viewpoint on the player
    /// and hands it to the video output, which projects the sphere.
    func applyViewpoint() {
        let view = viewpoint
        onOutputQueue { player in
            _ = player.updateViewpoint(
                Float(view.yaw),
                pitch: Float(view.pitch),
                roll: Float(view.roll),
                fov: Float(view.fieldOfView),
                absolute: true
            )
        }
    }

    func applyStereoMode() {
        let mode: VLCMediaPlayer.AudioStereoMode = switch stereoMode {
        case .automatic: .unset
        case .stereo: .stereo
        case .mono: .mono
        case .left: .left
        case .right: .right
        case .reversed: .rStereo
        case .dolbySurround: .dolbys
        }
        onOutputQueue { player in
            player.audioStereoMode = mode
        }
    }

    /// libVLC copies the equalizer's values when it's assigned, so a fresh
    /// one is built and assigned on every change.
    func applyEqualizer() {
        let settings = equalizer
        onOutputQueue { player in
            guard settings.isEnabled else {
                player.equalizer = nil
                return
            }
            let vlcEqualizer = VLCAudioEqualizer()
            vlcEqualizer.preAmplification = settings.preamp
            for (index, band) in vlcEqualizer.bands.enumerated() where settings.bands.indices.contains(index) {
                band.amplification = settings.bands[index]
            }
            player.equalizer = vlcEqualizer
        }
    }

    func applySubtitleScale() {
        let scale = subtitleScale
        onOutputQueue { player in
            player.currentSubTitleFontScale = scale
        }
    }

    func stepFrame(forward: Bool) {
        onOutputQueue { player in
            if forward {
                player.gotoNextFrame()
            } else {
                player.gotoPreviousFrame()
            }
        }
    }

    /// libVLC writes the file on its own thread; wait (up to three seconds)
    /// for it to appear.
    func saveSnapshot(to url: URL) async throws {
        // (Not `player.hasVideoOut` here: it waits for the same locks.)
        guard videoDimensions != nil else {
            throw PlaybackError(.engineFailure, "There\u{2019}s no picture to save.")
        }
        try? FileManager.default.removeItem(at: url)
        let path = url.path
        onOutputQueue { player in
            // VLCKit raises an exception when there's no video output.
            guard player.hasVideoOut else { return }
            player.saveVideoSnapshot(at: path, withWidth: 0, andHeight: 0)
        }
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 {
                return
            }
        }
        throw PlaybackError(.engineFailure, "VLC couldn\u{2019}t save the picture.")
    }
}

/// libVLC's equalizer presets and band frequencies.
public enum EqualizerPresets {
    public struct Preset: Hashable, Sendable, Identifiable {
        public let name: String
        public let preamp: Float
        public let bands: [Float]
        public var id: String { name }

        public var settings: EqualizerSettings {
            EqualizerSettings(isEnabled: true, presetName: name, preamp: preamp, bands: bands)
        }

        /// The name as shown: "Full Bass and Treble" for libVLC's "Full bass and treble".
        public var title: String { EqualizerPresets.title(for: name) }
    }

    /// Title case for libVLC's preset names, which are stored as libVLC
    /// spells them.
    public static func title(for name: String) -> String {
        name.split(separator: " ").enumerated().map { index, word in
            let lowered = word.lowercased()
            if index > 0, ["and", "of", "the"].contains(lowered) {
                return lowered
            }
            return word.prefix(1).uppercased() + word.dropFirst()
        }
        .joined(separator: " ")
    }

    /// Flat, Classical, Club, Dance, Full Bass… as libVLC defines them.
    @MainActor
    public static let all: [Preset] = VLCAudioEqualizer.presets.map { preset in
        let equalizer = VLCAudioEqualizer(preset: preset)
        return Preset(
            name: preset.name,
            preamp: equalizer.preAmplification,
            bands: EqualizerSettings.normalized(equalizer.bands.map(\.amplification))
        )
    }

    /// The centre frequency of each band, in hertz.
    @MainActor
    public static let frequencies: [Float] = {
        let values = VLCAudioEqualizer().bands.map(\.frequency).filter { $0 > 0 }
        return values.count == EqualizerSettings.bandCount ? values : EqualizerSettings.defaultFrequencies
    }()
}
