internal import VLCKit
import Foundation
import PlaybackCore

// Level 2 options for the VLC engine. Every call here was type-checked
// against the VLCKit 4.0.0a25 headers (videoFitMode, videoAspectRatio,
// setCropRatioWithNumerator(_:denominator:), adjustFilter, setDeinterlace,
// audioStereoMode, equalizer, currentSubTitleFontScale, gotoNextFrame,
// gotoPreviousFrame, saveVideoSnapshot(at:withWidth:andHeight:)).

extension VLCKitEngine {
    func applyAllOptions() {
        applyFillMode()
        applyAspectRatio()
        applyCrop()
        applyAdjustments()
        applyDeinterlace()
        applyStereoMode()
        applyEqualizer()
        if subtitleScale != 1 {
            player.currentSubTitleFontScale = subtitleScale
        }
    }

    func applyFillMode() {
        switch fillMode {
        case .fit: player.videoFitMode = .smaller
        case .fill: player.videoFitMode = .larger
        }
    }

    func applyAspectRatio() {
        player.videoAspectRatio = aspectRatio?.description
    }

    func applyCrop() {
        if let cropRatio {
            player.setCropRatioWithNumerator(UInt32(cropRatio.width), denominator: UInt32(cropRatio.height))
        } else {
            player.setCropRatioWithNumerator(0, denominator: 0)
        }
    }

    func applyAdjustments() {
        let values = videoAdjustments.clamped
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

    func applyDeinterlace() {
        switch deinterlace {
        case .automatic: player.setDeinterlace(.auto, withFilter: "yadif")
        case .on: player.setDeinterlace(.on, withFilter: "yadif")
        case .off: player.setDeinterlace(.off, withFilter: "yadif")
        }
    }

    func applyStereoMode() {
        switch stereoMode {
        case .automatic: player.audioStereoMode = .unset
        case .stereo: player.audioStereoMode = .stereo
        case .mono: player.audioStereoMode = .mono
        case .left: player.audioStereoMode = .left
        case .right: player.audioStereoMode = .right
        case .reversed: player.audioStereoMode = .rStereo
        case .dolbySurround: player.audioStereoMode = .dolbys
        }
    }

    /// libVLC copies the equalizer's values when it's assigned, so a fresh
    /// one is built and assigned on every change.
    func applyEqualizer() {
        guard equalizer.isEnabled else {
            player.equalizer = nil
            return
        }
        let vlcEqualizer = VLCAudioEqualizer()
        vlcEqualizer.preAmplification = equalizer.preamp
        for (index, band) in vlcEqualizer.bands.enumerated() where equalizer.bands.indices.contains(index) {
            band.amplification = equalizer.bands[index]
        }
        player.equalizer = vlcEqualizer
    }

    func stepFrame(forward: Bool) {
        if forward {
            player.gotoNextFrame()
        } else {
            player.gotoPreviousFrame()
        }
    }

    /// libVLC writes the file on its own thread; wait (up to three seconds)
    /// for it to appear.
    func saveSnapshot(to url: URL) async throws {
        guard player.hasVideoOut else {
            throw PlaybackError(.engineFailure, "There\u{2019}s no picture to save.")
        }
        try? FileManager.default.removeItem(at: url)
        player.saveVideoSnapshot(at: url.path, withWidth: 0, andHeight: 0)
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
