import Foundation
import Testing
@testable import PlaybackCore

@Suite("Player options")
struct PlayerOptionsTests {
    @Test func ratiosParseAndName() {
        #expect(VideoRatio(parsing: "16:9") == VideoRatio(16, 9))
        #expect(VideoRatio(parsing: "2.39:1") == VideoRatio(239, 100))
        #expect(VideoRatio(parsing: "1.85") == VideoRatio(185, 100))
        #expect(VideoRatio(parsing: " 4 : 3 ") == VideoRatio(4, 3))
        #expect(VideoRatio(parsing: "wide") == nil)
        #expect(VideoRatio(parsing: "0:1") == nil)
        #expect(VideoRatio(parsing: "1:2:3") == nil)
        #expect(VideoRatio(16, 9).description == "16:9")
        #expect(VideoRatio(239, 100).title == "2.39:1 (Scope)")
        #expect(VideoRatio(1, 1).title == "1:1 (Square)")
        #expect(VideoRatio(4, 3).title == "4:3")
        #expect(abs(VideoRatio(16, 9).value - 1.7778) < 0.001)
        // Every preset is distinct.
        #expect(Set(VideoRatio.aspectPresets).count == VideoRatio.aspectPresets.count)
        #expect(Set(VideoRatio.cropPresets).count == VideoRatio.cropPresets.count)
    }

    @Test func adjustmentsClampToLibVLCRanges() {
        let wild = VideoAdjustments(brightness: 5, contrast: -1, saturation: 9, hue: 400, gamma: 0)
        let clamped = wild.clamped
        #expect(clamped.brightness == 2)
        #expect(clamped.contrast == 0)
        #expect(clamped.saturation == 3)
        #expect(clamped.hue == 180)
        #expect(clamped.gamma == 0.01)
        #expect(VideoAdjustments.neutral.isNeutral)
        #expect(!clamped.isNeutral)
    }

    @Test func equalizerKeepsTenClampedBands() {
        let short = EqualizerSettings(isEnabled: true, preamp: 30, bands: [1, 2, 3])
        #expect(short.bands.count == EqualizerSettings.bandCount)
        #expect(short.bands.prefix(3) == [1, 2, 3])
        #expect(short.bands.suffix(7).allSatisfy { $0 == 0 })
        #expect(short.preamp == 20)
        let long = EqualizerSettings(bands: Array(repeating: -50, count: 14))
        #expect(long.bands.count == EqualizerSettings.bandCount)
        #expect(long.bands.allSatisfy { $0 == -20 })
        #expect(EqualizerSettings.clampGain(.nan) == 0)
        #expect(EqualizerSettings.frequencyLabel(62.5) == "62.5 Hz")
        #expect(EqualizerSettings.frequencyLabel(1_000) == "1 kHz")
        #expect(EqualizerSettings.frequencyLabel(16_000) == "16 kHz")
        #expect(EqualizerSettings.flat == EqualizerSettings())
    }

    @Test func equalizerSettingsRoundTrip() throws {
        let settings = EqualizerSettings(isEnabled: true, presetName: "Rock", preamp: -3, bands: [4, 3, -2, -4, -1, 2, 5, 6, 6, 6])
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(EqualizerSettings.self, from: data) == settings)
    }

    @Test func subtitleSizesGrow() {
        let scales = SubtitleSize.allCases.map(\.scale)
        #expect(scales == scales.sorted())
        #expect(SubtitleSize.standard.scale == 1)
    }

    @Test func abLoopCyclesThroughItsStates() {
        var loop = ABLoop()
        #expect(loop.phase == .off)
        #expect(loop.jumpTarget(at: 100) == nil)

        loop.advance(at: 30)
        #expect(loop.phase == .waitingForEnd)
        #expect(loop.start == 30)
        #expect(loop.jumpTarget(at: 100) == nil)

        // A second press within half a second is ignored.
        loop.advance(at: 30.2)
        #expect(loop.phase == .waitingForEnd)

        loop.advance(at: 45)
        #expect(loop.phase == .looping)
        #expect(loop.jumpTarget(at: 44.9) == nil)
        #expect(loop.jumpTarget(at: 45) == 30)
        #expect(loop.jumpTarget(at: 50) == 30)

        loop.advance(at: 40)
        #expect(loop.phase == .off)
        #expect(loop.start == nil && loop.end == nil)
    }

    @Test func abLoopSwapsWhenBComesBeforeA() {
        var loop = ABLoop()
        loop.advance(at: 60)
        loop.advance(at: 20)
        #expect(loop.start == 20)
        #expect(loop.end == 60)
        #expect(loop.phase == .looping)
    }
}

@Suite("Scrub previews")
struct ScrubPreviewPlanTests {
    @Test func longVideosGetTheTargetCount() {
        let plan = ScrubPreviewPlan(duration: 2 * 3_600, targetCount: 200)
        #expect(plan.count == 200)
        #expect(plan.interval == 36)
        #expect(plan.time(of: 0) == 18)
        #expect(plan.index(for: 0) == 0)
        #expect(plan.index(for: 35.9) == 0)
        #expect(plan.index(for: 36) == 1)
        #expect(plan.index(for: 99_999) == 199)
        #expect(plan.index(for: -5) == 0)
    }

    @Test func shortVideosUseTheMinimumInterval() {
        let plan = ScrubPreviewPlan(duration: 61, targetCount: 200, minimumInterval: 2)
        #expect(plan.interval == 2)
        #expect(plan.count == 31)
        // The last frame stays inside the video.
        #expect(plan.time(of: 30) <= 60.5)
    }

    @Test func emptyAndBrokenDurations() {
        #expect(ScrubPreviewPlan(duration: 0).count == 0)
        #expect(ScrubPreviewPlan(duration: .nan).count == 0)
        #expect(ScrubPreviewPlan(duration: .infinity).count == 0)
        #expect(ScrubPreviewPlan(duration: 0).generationOrder.isEmpty)
    }

    @Test func generationOrderIsCoarseToFineAndComplete() {
        let plan = ScrubPreviewPlan(duration: 1_000, targetCount: 100, minimumInterval: 1)
        let order = plan.generationOrder
        #expect(order.count == plan.count)
        #expect(Set(order) == Set(0..<plan.count))
        // Every 16th first.
        #expect(Array(order.prefix(7)) == [0, 16, 32, 48, 64, 80, 96])
        // Then the 8ths between them.
        #expect(order[7] == 8)
    }

    @Test func nearestSearchesOutwards() {
        let plan = ScrubPreviewPlan(duration: 100, targetCount: 50, minimumInterval: 1)
        let available: Set<Int> = [3, 10, 30]
        #expect(plan.nearest(to: 10) { available.contains($0) } == 10)
        #expect(plan.nearest(to: 7) { available.contains($0) } == 10)
        #expect(plan.nearest(to: 6) { available.contains($0) } == 3)
        #expect(plan.nearest(to: 49) { available.contains($0) } == 30)
        #expect(plan.nearest(to: 20) { _ in false } == nil)
    }

    @Test func plansRoundTrip() throws {
        let plan = ScrubPreviewPlan(duration: 5_400)
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(ScrubPreviewPlan.self, from: data) == plan)
    }
}

@Suite("Typed times")
struct TypedTimeTests {
    @Test func readsClockTimes() {
        #expect(PlaybackTimeFormatter.seconds(from: "45") == 45)
        #expect(PlaybackTimeFormatter.seconds(from: "1:30") == 90)
        #expect(PlaybackTimeFormatter.seconds(from: "62:03") == 3_723)
        #expect(PlaybackTimeFormatter.seconds(from: "1:02:03") == 3_723)
        #expect(PlaybackTimeFormatter.seconds(from: " 0:07 ") == 7)
    }

    @Test func readsUnits() {
        #expect(PlaybackTimeFormatter.seconds(from: "1h 2m 3s") == 3_723)
        #expect(PlaybackTimeFormatter.seconds(from: "45m") == 2_700)
        #expect(PlaybackTimeFormatter.seconds(from: "90s") == 90)
    }

    @Test func rejectsNonsense() {
        #expect(PlaybackTimeFormatter.seconds(from: "") == nil)
        #expect(PlaybackTimeFormatter.seconds(from: "abc") == nil)
        #expect(PlaybackTimeFormatter.seconds(from: "1:75") == nil)
        #expect(PlaybackTimeFormatter.seconds(from: "1:2:3:4") == nil)
        #expect(PlaybackTimeFormatter.seconds(from: "5x") == nil)
        #expect(PlaybackTimeFormatter.seconds(from: "12h30") == nil)
    }
}

@Suite("Subtitle style")
struct SubtitleStyleTests {
    @Test func theStandardStyleLeavesVLCAlone() {
        #expect(SubtitleStyle.standard.libVLCOptions.isEmpty)
        #expect(SubtitleStyle.standard.summary == "Default")
        #expect(EngineConfiguration().libVLCLibraryOptions == ["--no-play-and-pause", "--network-caching=1000"])
    }

    @Test func aStyleBecomesTextRendererOptions() {
        let style = SubtitleStyle(font: .serif, textColor: .yellow, isBold: true, outline: .thick, background: .translucent, position: .raised)
        #expect(style.libVLCOptions == [
            "--freetype-font=Georgia",
            "--freetype-color=\(0xFFE14D)",
            "--freetype-outline-thickness=6",
            "--freetype-bold",
            "--freetype-background-opacity=150",
            "--freetype-background-color=0",
            "--sub-margin=50",
        ])
        #expect(style.summary == "Yellow \u{00B7} Serif \u{00B7} Bold \u{00B7} See-Through Background \u{00B7} Outline Thick \u{00B7} Raised")
    }

    @Test func customOptionsStillWin() {
        let configuration = EngineConfiguration(customLibVLCOptions: "--freetype-color=255", subtitleStyle: SubtitleStyle(textColor: .green))
        let options = configuration.libVLCLibraryOptions
        let colours = options.filter { $0.hasPrefix("--freetype-color=") }
        #expect(colours.last == "--freetype-color=255")
    }

    @Test func encodingIsAMediaOption() {
        #expect(EngineConfiguration(subtitleEncoding: "Windows-1251").libVLCMediaOptions == [":subsdec-encoding=Windows-1251"])
        #expect(EngineConfiguration().libVLCMediaOptions.isEmpty)
        #expect(SubtitleEncoding.title(for: nil) == "Automatic")
        #expect(SubtitleEncoding.title(for: "Big5") == "Chinese, Traditional (Big5)")
    }

    @Test func colourComponents() {
        let white = SubtitleStyle.TextColor.white.components
        #expect(white.red == 1 && white.green == 1 && white.blue == 1)
    }
}
