import DesignSystem
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// Every Level 2 option, in a glass panel over the player rather than a
/// separate screen: audio and subtitles with timing, speed, the picture
/// (fit, shape, crop, colours, deinterlacing), sound (equalizer, stereo),
/// chapters, tools (A–B loop, frame by frame, snapshot, jump to time) and
/// what's playing. Plain-language labels only ("Subtitle Timing", never
/// "SPU delay").
public struct PlaybackOptionsView: View {
    public enum Page: Hashable {
        case audio, subtitles, onlineSubtitles, subtitleStyle, encoding, speed, picture, colours, sound, titles, chapters, tools, info
    }

    @Environment(PlaybackSession.self) private var session
    @State private var path: [Page] = []

    private let isVideo: Bool
    private let onClose: () -> Void
    private let onAddSubtitleFile: () -> Void
    private let onSnapshot: () -> Void
    private var isSnapshot = false

    /// - Parameters:
    ///   - isVideo: Video gets every page; music gets speed, sound and info.
    ///   - onAddSubtitleFile: Shows the file picker for a subtitle file.
    ///   - onSnapshot: Saves the frame on screen.
    public init(isVideo: Bool, onClose: @escaping () -> Void, onAddSubtitleFile: @escaping () -> Void = {}, onSnapshot: @escaping () -> Void = {}) {
        self.isVideo = isVideo
        self.onClose = onClose
        self.onAddSubtitleFile = onAddSubtitleFile
        self.onSnapshot = onSnapshot
    }

    /// For snapshot tests: opens on `page`, with the page laid out in full
    /// on a flat dark panel, since ImageRenderer draws neither scroll views
    /// nor Liquid Glass.
    init(snapshotOf page: Page?, isVideo: Bool) {
        self.init(isVideo: isVideo, onClose: {})
        _path = State(initialValue: page.map { [$0] } ?? [])
        isSnapshot = true
    }

    private var controller: PlaybackController { session.controller }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if isSnapshot {
                pageContent
            } else {
                ScrollView {
                    pageContent
                }
                .scrollIndicators(.hidden)
                .id(path.last)
                .transition(.push(from: .trailing))
            }
        }
        .foregroundStyle(Palette.primaryOnDark)
        .background {
            if isSnapshot {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(white: 0.14))
            }
        }
        .glassEffect(isSnapshot ? .identity : .regular.tint(.black.opacity(0.45)), in: .rect(cornerRadius: 28))
        .environment(\.colorScheme, .dark)
        .animation(Motion.standard, value: path)
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            page(path.last)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if !path.isEmpty {
                PlayerIconButton("Back", systemImage: "chevron.backward") {
                    path.removeLast()
                }
            }
            Text(title(for: path.last))
                .font(.headline)
                .lineLimit(1)
                .padding(.leading, path.isEmpty ? 10 : 0)
            Spacer(minLength: 8)
            PlayerIconButton("Close", systemImage: "xmark", help: "Close (Esc)", action: onClose)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func title(for page: Page?) -> String {
        switch page {
        case nil: isVideo ? "Options" : "Playback"
        case .audio: "Audio"
        case .subtitles: "Subtitles"
        case .onlineSubtitles: session.onlineSubtitles.map { "Search \($0.name)" } ?? "Search Online"
        case .subtitleStyle: "Subtitle Style"
        case .encoding: "Text Encoding"
        case .speed: "Speed"
        case .picture: "Picture"
        case .colours: "Colours"
        case .sound: "Sound"
        case .titles: controller.isDisc ? "Disc" : "Titles"
        case .chapters: "Chapters"
        case .tools: "Tools"
        case .info: "Media Info"
        }
    }

    @ViewBuilder
    private func page(_ page: Page?) -> some View {
        switch page {
        case nil: rootPage
        case .audio: audioPage
        case .subtitles: subtitlesPage
        case .onlineSubtitles: OnlineSubtitlesPage(onAdded: {
            // The download took a while: only leave the page if it's still showing.
            if path.last == .onlineSubtitles {
                path.removeLast()
            }
        })
        case .subtitleStyle: subtitleStylePage
        case .encoding: encodingPage
        case .speed: speedPage
        case .picture: picturePage
        case .colours: coloursPage
        case .sound: soundPage
        case .titles: titlesPage
        case .chapters: chaptersPage
        case .tools: toolsPage
        case .info: infoPage
        }
    }

    // MARK: Root

    @ViewBuilder
    private var rootPage: some View {
        if isVideo {
            OptionsGroup {
                NavigationRow("Audio", systemImage: "speaker.wave.2", value: selectedAudioName) { path.append(.audio) }
                NavigationRow("Subtitles", systemImage: "captions.bubble", value: selectedSubtitleName) { path.append(.subtitles) }
                NavigationRow("Speed", systemImage: "gauge.with.dots.needle.50percent", value: PlaybackSpeeds.label(controller.rate)) { path.append(.speed) }
            }
            OptionsGroup {
                NavigationRow("Picture", systemImage: "aspectratio", value: pictureSummary) { path.append(.picture) }
                NavigationRow("Sound", systemImage: "slider.vertical.3", value: soundSummary) { path.append(.sound) }
                if controller.hasDiscMenu || MediaTitle.offersChoice(controller.titles) {
                    NavigationRow(controller.isDisc ? "Disc" : "Titles", systemImage: controller.isDisc ? "opticaldisc" : "film.stack", value: currentTitleName) { path.append(.titles) }
                }
                if !controller.chapters.isEmpty {
                    NavigationRow("Chapters", systemImage: "list.bullet.rectangle", value: currentChapter?.displayTitle) { path.append(.chapters) }
                }
            }
            OptionsGroup {
                NavigationRow("Tools", systemImage: "wand.and.rays", value: toolsSummary) { path.append(.tools) }
                NavigationRow("Media Info", systemImage: "info.circle", value: controller.activeEngine?.displayName) { path.append(.info) }
            }
        } else {
            OptionsGroup {
                NavigationRow("Speed", systemImage: "gauge.with.dots.needle.50percent", value: PlaybackSpeeds.label(controller.rate)) { path.append(.speed) }
                NavigationRow("Sound", systemImage: "slider.vertical.3", value: soundSummary) { path.append(.sound) }
                if controller.audioTracks.count > 1 {
                    NavigationRow("Audio", systemImage: "speaker.wave.2", value: selectedAudioName) { path.append(.audio) }
                }
                NavigationRow("Media Info", systemImage: "info.circle", value: controller.activeEngine?.displayName) { path.append(.info) }
            }
        }
    }

    private var selectedAudioName: String? {
        controller.audioTracks.first(where: \.isSelected)?.displayName()
    }

    private var selectedSubtitleName: String {
        controller.subtitleTracks.first(where: \.isSelected)?.displayName() ?? "Off"
    }

    private var pictureSummary: String {
        if controller.isSpherical {
            return "360\u{00B0}"
        }
        var parts = [controller.zoom.isZoomed ? "Zoom \(controller.zoom.title)" : controller.fillMode.title]
        if !controller.transform.isIdentity { parts.append(controller.transform.summary) }
        if let ratio = controller.aspectRatio { parts.append(ratio.description) }
        if let crop = controller.cropRatio { parts.append("Crop \(crop.description)") }
        if !controller.videoAdjustments.isNeutral { parts.append("Adjusted") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var soundSummary: String {
        if controller.equalizer.isEnabled {
            return controller.equalizer.presetName.map { EqualizerPresets.title(for: $0) } ?? "Equalizer On"
        }
        return controller.stereoMode == .automatic ? "Equalizer Off" : controller.stereoMode.title
    }

    private var toolsSummary: String? {
        switch controller.abLoop.phase {
        case .off: nil
        case .waitingForEnd: "Loop: set B"
        case .looping: "Looping"
        }
    }

    /// "Title 2", "Menu", or the title's own name.
    private var currentTitleName: String? {
        guard let current = controller.currentTitle else { return nil }
        if current.isMenu {
            return current.displayName(number: 0)
        }
        return MediaTitle.numbered(controller.titles)
            .first { $0.title.id == current.id }
            .map { $0.title.displayName(number: $0.number) }
    }

    private var currentChapter: Chapter? {
        controller.chapters.last(where: { $0.start <= controller.currentTime + 0.5 })
    }

    // MARK: Audio

    @ViewBuilder
    private var audioPage: some View {
        if !controller.audioTracks.isEmpty {
            OptionsGroup(title: "Language") {
                ForEach(controller.audioTracks) { track in
                    CheckRow(track.displayName(), isSelected: track.isSelected) {
                        controller.selectAudioTrack(track)
                    }
                }
            }
        }
        OptionsGroup(title: "Timing", footer: timingFooter) {
            TimingControl(title: "Audio Timing", value: controller.audioDelay, step: 0.05) { value in
                Task { await controller.setAudioDelay(value) }
            }
        }
        if isVideo {
            OptionsGroup(title: "Channels") {
                stereoRows
            }
        }
    }

    private var timingFooter: String? {
        controller.capabilities.contains(.audioDelay) ? nil : "Changing timing moves this video to the VLC engine at the same position."
    }

    // MARK: Subtitles

    @ViewBuilder
    private var subtitlesPage: some View {
        OptionsGroup(title: "Language") {
            CheckRow("Off", isSelected: !controller.subtitleTracks.contains(where: \.isSelected)) {
                controller.selectSubtitleTrack(nil)
            }
            ForEach(controller.subtitleTracks) { track in
                CheckRow(track.displayName(), isSelected: track.isSelected) {
                    controller.selectSubtitleTrack(track)
                }
            }
            ActionRow("Add Subtitle File\u{2026}", systemImage: "doc.badge.plus") {
                onAddSubtitleFile()
            }
            if let provider = session.onlineSubtitles, controller.currentItem?.url.isFileURL == true {
                NavigationRow("Search \(provider.name)", systemImage: "magnifyingglass", value: nil) {
                    path.append(.onlineSubtitles)
                }
            }
        }
        if showsSecondSubtitle {
            OptionsGroup(title: "Second Subtitle", footer: "Shows a second language at the same time, for example to learn one alongside the other.") {
                CheckRow("Off", isSelected: !controller.subtitleTracks.contains(where: \.isSecondary)) {
                    controller.selectSecondarySubtitleTrack(nil)
                }
                ForEach(controller.subtitleTracks.filter { !$0.isSelected }) { track in
                    CheckRow(track.displayName(), isSelected: track.isSecondary) {
                        controller.selectSecondarySubtitleTrack(track)
                    }
                }
            }
        }
        OptionsGroup(title: "Timing", footer: timingFooter) {
            TimingControl(title: "Subtitle Timing", value: controller.subtitleDelay, step: 0.1) { value in
                Task { await controller.setSubtitleDelay(value) }
            }
        }
        OptionsGroup(title: "Text Size") {
            CapsuleChoices(SubtitleSize.allCases, selection: controller.subtitleSize, title: \.title) { size in
                Task { await session.setSubtitleSize(size) }
            }
            .padding(14)
        }
        OptionsGroup {
            NavigationRow("Style", systemImage: "textformat", value: controller.subtitleStyle.summary) {
                path.append(.subtitleStyle)
            }
            NavigationRow("Text Encoding", systemImage: "character.book.closed", value: SubtitleEncoding.title(for: controller.subtitleEncoding)) {
                path.append(.encoding)
            }
        }
    }

    /// Two subtitle tracks at once: VLC only, once one is showing.
    private var showsSecondSubtitle: Bool {
        controller.capabilities.contains(.dualSubtitles)
            && controller.subtitleTracks.count > 1
            && controller.subtitleTracks.contains(where: \.isSelected)
    }

    // MARK: Subtitle style

    @ViewBuilder
    private var subtitleStylePage: some View {
        let style = controller.subtitleStyle
        SubtitleStylePreview(style: style, size: controller.subtitleSize)
        OptionsGroup(title: "Font") {
            CapsuleChoices(SubtitleStyle.Font.allCases, selection: style.font, title: \.title) { font in
                update { $0.font = font }
            }
            .padding(14)
            ToggleRow("Bold", isOn: style.isBold) { isBold in
                update { $0.isBold = isBold }
            }
        }
        OptionsGroup(title: "Colour") {
            ColourSwatches(selection: style.textColor) { colour in
                update { $0.textColor = colour }
            }
            .padding(14)
        }
        OptionsGroup(title: "Outline") {
            CapsuleChoices(SubtitleStyle.Outline.allCases, selection: style.outline, title: \.title) { outline in
                update { $0.outline = outline }
            }
            .padding(14)
        }
        OptionsGroup(title: "Background") {
            CapsuleChoices(SubtitleStyle.Background.allCases, selection: style.background, title: \.title) { background in
                update { $0.background = background }
            }
            .padding(14)
        }
        OptionsGroup(title: "Position", footer: styleFooter) {
            CapsuleChoices(SubtitleStyle.Position.allCases, selection: style.position, title: \.title) { position in
                update { $0.position = position }
            }
            .padding(14)
            if !style.isStandard {
                ActionRow("Use the Default Style", systemImage: "arrow.counterclockwise") {
                    Task { await session.setSubtitleStyle(.standard) }
                }
            }
        }
    }

    private var styleFooter: String {
        var footer = "For subtitles that are plain text (SRT, WebVTT, MP4). Styled subtitles (ASS) keep their own look, and picture subtitles from discs can\u{2019}t be restyled."
        if controller.activeEngine == .vlc {
            footer += " The video restarts at the same place to apply a change."
        }
        return footer
    }

    private func update(_ change: (inout SubtitleStyle) -> Void) {
        var style = controller.subtitleStyle
        change(&style)
        Task { await session.setSubtitleStyle(style) }
    }

    // MARK: Text encoding

    private var encodingPage: some View {
        OptionsGroup(footer: "For subtitle files that show the wrong letters. Unicode files are always read correctly. The video restarts at the same place to apply a change.") {
            CheckRow("Automatic", isSelected: controller.subtitleEncoding == nil) {
                Task { await session.setSubtitleEncoding(nil) }
            }
            ForEach(SubtitleEncoding.all) { encoding in
                CheckRow(encoding.title, isSelected: controller.subtitleEncoding == encoding.id) {
                    Task { await session.setSubtitleEncoding(encoding.id) }
                }
            }
        }
    }

    // MARK: Speed

    private var speedPage: some View {
        OptionsGroup(footer: "Speech keeps its natural pitch at every speed. Speeds above 2\u{00D7} use the VLC engine.") {
            CapsuleChoices(PlaybackSpeeds.all, selection: controller.rate, title: PlaybackSpeeds.label) { rate in
                Task { await controller.setRate(rate) }
            }
            .padding(14)
        }
    }

    // MARK: Picture

    @ViewBuilder
    private var picturePage: some View {
        if controller.isSpherical {
            sphericalViewGroup
        }
        OptionsGroup(title: "Size", footer: "Fill trims the edges so the picture covers the whole player. Pinch the video to switch, and pinch further to zoom in.") {
            CapsuleChoices(VideoFillMode.allCases, selection: controller.fillMode, title: \.title) { mode in
                controller.setFillMode(mode)
            }
            .padding(14)
        }
        if !controller.isSpherical {
            OptionsGroup(title: "Zoom", footer: "Drag the video to look around while it\u{2019}s zoomed in.") {
                ZoomStepper(zoom: controller.zoom) { zoom in
                    controller.setZoom(zoom)
                }
            }
            OptionsGroup(title: "Turn and Flip", footer: "For videos filmed sideways or mirrored.") {
                TransformButtons(transform: controller.transform) { transform in
                    controller.setTransform(transform)
                }
            }
        }
        OptionsGroup(title: "Shape") {
            CapsuleChoices([VideoRatio?.none] + VideoRatio.aspectPresets.map(Optional.some), selection: controller.aspectRatio, title: { $0?.title ?? "Original" }) { ratio in
                Task { await controller.setAspectRatio(ratio) }
            }
            .padding(14)
        }
        OptionsGroup(title: "Crop") {
            CapsuleChoices([VideoRatio?.none] + VideoRatio.cropPresets.map(Optional.some), selection: controller.cropRatio, title: { $0?.title ?? "None" }) { ratio in
                Task { await controller.setCropRatio(ratio) }
            }
            .padding(14)
        }
        OptionsGroup {
            NavigationRow("Colours", systemImage: "camera.filters", value: controller.videoAdjustments.isNeutral ? "Original" : "Adjusted") {
                path.append(.colours)
            }
        }
        OptionsGroup(title: "Deinterlacing", footer: "For DVDs and TV recordings that show combing on movement. Shape, crop, colours and deinterlacing use the VLC engine.") {
            CapsuleChoices(DeinterlaceMode.allCases, selection: controller.deinterlace, title: \.title) { mode in
                Task { await controller.setDeinterlace(mode) }
            }
            .padding(14)
        }
        if controller.deinterlace != .off {
            OptionsGroup(title: "Deinterlacing Method", footer: controller.deinterlaceFilter.detail) {
                CapsuleChoices(DeinterlaceFilter.allCases, selection: controller.deinterlaceFilter, title: \.title) { filter in
                    Task { await controller.setDeinterlaceFilter(filter) }
                }
                .padding(14)
            }
        }
    }

    /// A 360° video: how close you are, and back to straight ahead.
    @ViewBuilder
    private var sphericalViewGroup: some View {
        let viewpoint = controller.viewpoint
        OptionsGroup(title: "360\u{00B0} View", footer: "Drag the video to look around. Pinch, or use the slider, to go closer.") {
            AdjustmentSlider(
                title: "Field of View",
                value: viewpoint.fieldOfView,
                range: Viewpoint.fieldOfViewRange,
                neutral: Viewpoint.defaultFieldOfView,
                unit: "\u{00B0}"
            ) { value in
                controller.setViewpoint(Viewpoint(yaw: viewpoint.yaw, pitch: viewpoint.pitch, roll: viewpoint.roll, fieldOfView: value))
            }
            ActionRow("Look Straight Ahead", systemImage: "scope") {
                controller.setViewpoint(.straightAhead)
            }
            .disabled(viewpoint.isStraightAhead)
        }
    }

    // MARK: Colours

    @ViewBuilder
    private var coloursPage: some View {
        let adjustments = controller.videoAdjustments
        OptionsGroup {
            AdjustmentSlider(title: "Brightness", value: Double(adjustments.brightness), range: 0...2, neutral: 1) { value in
                update { $0.brightness = Float(value) }
            }
            AdjustmentSlider(title: "Contrast", value: Double(adjustments.contrast), range: 0...2, neutral: 1) { value in
                update { $0.contrast = Float(value) }
            }
            AdjustmentSlider(title: "Saturation", value: Double(adjustments.saturation), range: 0...3, neutral: 1) { value in
                update { $0.saturation = Float(value) }
            }
            AdjustmentSlider(title: "Hue", value: Double(adjustments.hue), range: -180...180, neutral: 0, unit: "\u{00B0}") { value in
                update { $0.hue = Float(value) }
            }
            AdjustmentSlider(title: "Gamma", value: Double(adjustments.gamma), range: 0.2...3, neutral: 1) { value in
                update { $0.gamma = Float(value) }
            }
        }
        OptionsGroup {
            ActionRow("Reset Colours", systemImage: "arrow.counterclockwise") {
                Task { await controller.setVideoAdjustments(.neutral) }
            }
            .disabled(adjustments.isNeutral)
        }
    }

    private func update(_ change: (inout VideoAdjustments) -> Void) {
        var adjustments = controller.videoAdjustments
        change(&adjustments)
        Task { await controller.setVideoAdjustments(adjustments) }
    }

    // MARK: Sound

    @ViewBuilder
    private var soundPage: some View {
        let equalizer = controller.equalizer
        OptionsGroup(footer: "The equalizer uses the VLC engine while it\u{2019}s on.") {
            ToggleRow("Equalizer", isOn: equalizer.isEnabled) { [session] isOn in
                var settings = equalizer
                settings.isEnabled = isOn
                Task { await session.setEqualizer(settings) }
            }
        }
        if equalizer.isEnabled {
            OptionsGroup(title: "Presets") {
                CapsuleChoices(EqualizerPresets.all.map(\.name), selection: equalizer.presetName ?? "", title: { EqualizerPresets.title(for: $0) }) { name in
                    guard let preset = EqualizerPresets.all.first(where: { $0.name == name }) else { return }
                    Task { await session.setEqualizer(preset.settings) }
                }
                .padding(14)
            }
            OptionsGroup(title: "Bands") {
                EqualizerBands(settings: equalizer) { settings in
                    Task { await session.setEqualizer(settings) }
                }
                .padding(14)
            }
        }
        if !isVideo {
            OptionsGroup(title: "Sound Check", footer: soundCheckFooter) {
                CapsuleChoices(ReplayGainMode.allCases, selection: controller.replayGain.mode, title: \.title) { [session] mode in
                    var settings = controller.replayGain
                    settings.mode = mode
                    Task { await session.setReplayGain(settings) }
                }
                .padding(14)
            }
            OptionsGroup(title: "Channels") {
                stereoRows
            }
        }
    }

    /// What levelling does to this song.
    private var soundCheckFooter: String {
        let base = "Plays songs at the same loudness, using the ReplayGain values saved in them."
        guard controller.replayGain.mode != .off, let item = controller.currentItem else { return base }
        guard item.replayGain?.hasGain == true else {
            return base + " This song has none, so it plays as recorded."
        }
        let gain = controller.replayGain.gain(for: item.replayGain)
        let text = gain.formatted(.number.precision(.fractionLength(1)))
        return base + " This song plays \(gain > 0 ? "+" : "")\(text) dB."
    }

    @ViewBuilder
    private var stereoRows: some View {
        ForEach(StereoMode.allCases, id: \.self) { mode in
            CheckRow(mode.title, isSelected: controller.stereoMode == mode) {
                Task { await controller.setStereoMode(mode) }
            }
        }
    }

    // MARK: Titles

    @ViewBuilder
    private var titlesPage: some View {
        if controller.hasDiscMenu {
            OptionsGroup(footer: controller.isShowingDiscMenu ? "Choose with the arrows and Select below the menu, or with the keyboard\u{2019}s arrow keys and Return." : nil) {
                ActionRow("Go to Disc Menu", systemImage: "opticaldisc") {
                    controller.navigateDisc(.menu)
                    onClose()
                }
                if controller.currentItem?.disc == .bluray {
                    ActionRow("Pop-Up Menu", systemImage: "rectangle.stack") {
                        controller.navigateDisc(.popUpMenu)
                        onClose()
                    }
                }
            }
        }
        let numbered = MediaTitle.numbered(controller.titles)
        if !numbered.isEmpty {
            OptionsGroup(title: "Titles") {
                ForEach(numbered, id: \.title.id) { entry in
                    CheckRow(entry.title.displayName(number: entry.number), detail: titleDetail(entry.title), isSelected: entry.title.id == controller.currentTitleIndex) {
                        controller.selectTitle(entry.title)
                        onClose()
                    }
                }
            }
        }
    }

    /// "Main Feature · 1:52:04 · 24 chapters" for a disc's film.
    private func titleDetail(_ title: MediaTitle) -> String? {
        let isMain = controller.isDisc && MediaTitle.offersChoice(controller.titles) && title.id == controller.mainTitle?.id
        let parts = [isMain ? "Main Feature" : nil, title.details].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    // MARK: Chapters

    private var chaptersPage: some View {
        OptionsGroup {
            ForEach(controller.chapters) { chapter in
                CheckRow(chapter.displayTitle, detail: PlaybackTimeFormatter.string(from: chapter.start, referenceDuration: controller.duration), isSelected: chapter.id == currentChapter?.id) {
                    controller.selectChapter(chapter)
                    onClose()
                }
            }
        }
    }

    // MARK: Tools

    @ViewBuilder
    private var toolsPage: some View {
        OptionsGroup(title: "A\u{2013}B Loop", footer: loopFooter) {
            ActionRow(loopButtonTitle, systemImage: "repeat") {
                controller.advanceABLoop()
            }
        }
        OptionsGroup(title: "Frame by Frame", footer: "Pauses the video. With a keyboard, the comma and full stop keys step too.") {
            HStack(spacing: 12) {
                frameButton(forward: false)
                frameButton(forward: true)
            }
            .padding(14)
        }
        OptionsGroup {
            ActionRow(snapshotTitle, systemImage: "camera") {
                onSnapshot()
            }
            .disabled(!controller.capabilities.contains(.snapshots))
        }
        OptionsGroup(title: "Go To") {
            JumpToTimeField(duration: controller.duration) { seconds in
                Task { await controller.seek(to: seconds) }
            }
            .padding(14)
        }
    }

    private var loopButtonTitle: String {
        switch controller.abLoop.phase {
        case .off: "Set Start (A)"
        case .waitingForEnd: "Set End (B)"
        case .looping: "Stop Looping"
        }
    }

    private var loopFooter: String {
        let format = { (time: TimeInterval) in PlaybackTimeFormatter.string(from: time, referenceDuration: controller.duration) }
        switch controller.abLoop.phase {
        case .off:
            return "Mark where the loop starts, then where it ends."
        case .waitingForEnd:
            return "Starts at \(format(controller.abLoop.start ?? 0)). Now mark the end."
        case .looping:
            return "Playing \(format(controller.abLoop.start ?? 0))\u{2013}\(format(controller.abLoop.end ?? 0)) on repeat."
        }
    }

    private var snapshotTitle: String {
        #if os(macOS)
        "Save Picture to Pictures Folder"
        #else
        "Save Picture to Photos"
        #endif
    }

    private func frameButton(forward: Bool) -> some View {
        Button {
            controller.stepFrame(forward: forward)
        } label: {
            Label(forward ? "Next Frame" : "Previous Frame", systemImage: forward ? "forward.frame" : "backward.frame")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Info

    private var infoPage: some View {
        MediaInfoPage(controller: controller)
    }
}

/// VLC's Codec Information, in plain language: the engine, the file, every
/// stream, and live figures while it plays.
private struct MediaInfoPage: View {
    let controller: PlaybackController
    @State private var info: MediaInfo?
    @State private var statistics: PlaybackStatistics?
    @State private var fileSize: Int64?

    var body: some View {
        Group {
            engineGroup
            fileGroup
            if let info {
                ForEach(Array(info.video.enumerated()), id: \.element.id) { index, stream in
                    OptionsGroup(title: info.video.count > 1 ? "Video \(index + 1)" : "Video") {
                        videoRows(stream)
                    }
                }
                if !info.audio.isEmpty {
                    OptionsGroup(title: "Audio") {
                        ForEach(Array(info.audio.enumerated()), id: \.element.id) { index, stream in
                            StreamRow(title: stream.displayName(index: index), detail: audioDetail(stream), isSelected: stream.isSelected)
                        }
                    }
                }
                if !info.subtitles.isEmpty {
                    OptionsGroup(title: "Subtitles") {
                        ForEach(Array(info.subtitles.enumerated()), id: \.element.id) { index, stream in
                            StreamRow(title: stream.displayName(index: index), detail: subtitleDetail(stream), isSelected: stream.isSelected)
                        }
                    }
                }
            }
            if let statistics, statistics.inputBitrate > 0 || controller.hasVideo {
                OptionsGroup(title: "While Playing") {
                    if statistics.inputBitrate > 0 {
                        InfoRow("Reading", value: MediaInfoFormat.bitrate(statistics.inputBitrate))
                    }
                    if controller.hasVideo {
                        InfoRow("Dropped Frames", value: "\(statistics.lostPictures)")
                    }
                }
            }
        }
        .task(id: refreshKey) {
            fileSize = Self.fileSize(of: controller.currentItem?.url)
            var rounds = 0
            while !Task.isCancelled {
                if rounds % 3 == 0 {
                    // Tracks can change while playing (a subtitle file added).
                    info = await controller.mediaInfo()
                }
                statistics = controller.statistics
                rounds += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var refreshKey: String {
        "\(controller.currentItem?.id.uuidString ?? "")-\(controller.activeEngine?.rawValue ?? "")"
    }

    // MARK: Groups

    private var engineGroup: some View {
        OptionsGroup(title: "Engine") {
            InfoRow("Playing With", value: controller.activeEngine?.displayName ?? "\u{2014}")
            if let reason = controller.routingReason {
                InfoRow("Why", value: reason.explanation)
            }
            if let engine = controller.activeEngine, let other = otherEngine(than: engine) {
                ActionRow("Switch to \(other.displayName)", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await controller.switchEngine(to: other) }
                }
            }
        }
    }

    @ViewBuilder
    private var fileGroup: some View {
        OptionsGroup(title: controller.isDisc ? "Disc" : "File") {
            if let item = controller.currentItem, let disc = item.disc {
                // A disc's folder is VIDEO_TS (or the one holding BDMV); name the one around it.
                let folder = item.url.lastPathComponent.uppercased() == "VIDEO_TS" ? item.url.deletingLastPathComponent() : item.url
                InfoRow("Name", value: folder.lastPathComponent)
                InfoRow("Format", value: DiscLayout.imageExtensions.contains(item.url.pathExtension.lowercased()) ? "\(disc.title) image" : "\(disc.title) folder")
                if let title = controller.currentTitle {
                    InfoRow("Playing", value: title.isMenu ? "Menu" : MediaTitle.numbered(controller.titles).first { $0.title.id == title.id }.map { $0.title.displayName(number: $0.number) } ?? "Title")
                }
            } else if let url = controller.currentItem?.url {
                InfoRow("Name", value: url.isFileURL ? url.lastPathComponent : url.absoluteString)
                if let format = ContainerFormat(url: url).displayName {
                    InfoRow("Format", value: format)
                }
            }
            if let fileSize {
                InfoRow("Size", value: MediaInfoFormat.fileSize(fileSize))
            }
            if let duration = controller.duration {
                InfoRow("Length", value: PlaybackTimeFormatter.string(from: duration))
                if let fileSize, duration > 0 {
                    InfoRow("Overall Bitrate", value: MediaInfoFormat.bitrate(Double(fileSize) * 8 / duration))
                }
            }
        }
    }

    @ViewBuilder
    private func videoRows(_ stream: MediaInfo.Stream) -> some View {
        InfoRow("Codec", value: stream.codec ?? stream.fourCC ?? "Unknown")
        if let width = stream.width, let height = stream.height {
            let badge = VideoDimensions(width: width, height: height).resolutionBadge
            InfoRow("Resolution", value: "\(width) \u{00D7} \(height) (\(badge))")
        }
        if let frameRate = stream.frameRate {
            InfoRow("Frame Rate", value: MediaInfoFormat.frameRate(frameRate))
        }
        if let range = stream.dynamicRange {
            InfoRow("Dynamic Range", value: range)
        }
        if let rotation = stream.rotation, rotation != 0 {
            InfoRow("Rotation", value: "\(rotation)\u{00B0}")
        }
        if stream.isSpherical {
            InfoRow("Projection", value: "360\u{00B0}")
        }
        if let bitrate = stream.bitrate {
            InfoRow("Bitrate", value: MediaInfoFormat.bitrate(Double(bitrate)))
        }
    }

    private func audioDetail(_ stream: MediaInfo.Stream) -> String {
        var parts: [String] = [stream.codec ?? stream.fourCC ?? "Unknown"]
        if let channels = stream.channels { parts.append(MediaInfoFormat.channels(channels)) }
        if let rate = stream.sampleRate { parts.append(MediaInfoFormat.sampleRate(rate)) }
        if let bitrate = stream.bitrate { parts.append(MediaInfoFormat.bitrate(Double(bitrate))) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func subtitleDetail(_ stream: MediaInfo.Stream) -> String {
        var parts: [String] = [stream.codec ?? stream.fourCC ?? "Unknown"]
        if let encoding = stream.textEncoding { parts.append(encoding) }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The engine to offer switching to, if it can open this file at all.
    private func otherEngine(than engine: EngineKind) -> EngineKind? {
        guard engine == .vlc else { return .vlc }
        guard let item = controller.currentItem, item.disc == nil,
              ContainerFormat(url: item.url).support != .vlcOnly else { return nil }
        return .avFoundation
    }

    private static func fileSize(of url: URL?) -> Int64? {
        guard let url, url.isFileURL,
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return Int64(size)
    }
}

/// One audio or subtitle stream: its name, a check when it's playing, and its format.
private struct StreamRow: View {
    let title: String
    let detail: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.bold))
                .frame(width: 18)
                .opacity(isSelected ? 1 : 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryOnDark)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Places the options panel over a player: at the top right on wide
/// screens, from the bottom on narrow ones (iPhone in portrait).
struct PlayerOptionsLayer: View {
    let isVideo: Bool
    var topInset: CGFloat = 0
    let onClose: () -> Void
    var onAddSubtitleFile: () -> Void = {}
    var onSnapshot: () -> Void = {}

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 560
            PlaybackOptionsView(isVideo: isVideo, onClose: onClose, onAddSubtitleFile: onAddSubtitleFile, onSnapshot: onSnapshot)
                .frame(width: compact ? proxy.size.width - 24 : min(390, proxy.size.width - 24))
                .frame(maxHeight: compact ? proxy.size.height * 0.72 : proxy.size.height - topInset - 24)
                // Taps inside the panel stay there; taps beside it close it.
                .contentShape(Rectangle())
                .onTapGesture {}
                .padding(12)
                .padding(.top, compact ? 0 : topInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .bottom : .topTrailing)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

// MARK: - Building blocks

/// A line of sample text in the chosen subtitle style, over a dark frame.
private struct SubtitleStylePreview: View {
    let style: SubtitleStyle
    let size: SubtitleSize

    var body: some View {
        let colour = style.textColor.components
        let text = Text("The tide turns at midnight.")
            .font(.custom(style.font == .standard ? "Helvetica Neue" : style.font.familyName, size: 17 * CGFloat(size.scale)))
            .fontWeight(style.isBold ? .bold : .medium)
            .foregroundStyle(Color(red: colour.red, green: colour.green, blue: colour.blue))
        ZStack(alignment: style.position == .bottom ? .bottom : .center) {
            LinearGradient(colors: [Color(white: 0.32), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
            text
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(style.outline == .none ? 0 : 0.9), radius: CGFloat(style.outline.thickness) / 2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(Double(style.background.opacity) / 255), in: RoundedRectangle(cornerRadius: 4))
                .padding(.bottom, style.position == .bottom ? 14 : 0)
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(Text("Preview of the subtitle style"))
    }
}

/// The text colours as round swatches.
private struct ColourSwatches: View {
    let selection: SubtitleStyle.TextColor
    let onSelect: (SubtitleStyle.TextColor) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(SubtitleStyle.TextColor.allCases) { colour in
                let components = colour.components
                let isSelected = colour == selection
                Button {
                    onSelect(colour)
                } label: {
                    Circle()
                        .fill(Color(red: components.red, green: components.green, blue: components.blue))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle()
                                .strokeBorder(.white, lineWidth: isSelected ? 3 : 0)
                                .padding(-5)
                        }
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(colour.title))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

/// A rounded group of rows, like an inset grouped list on iOS.
private struct OptionsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondaryOnDark)
                    .padding(.horizontal, 6)
            }
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryOnDark)
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Highlights rows on hover and press.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBackground(configuration: configuration)
    }

    private struct RowBackground: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background(Color.white.opacity(configuration.isPressed ? 0.14 : (isHovering ? 0.07 : 0)))
                .onHover { isHovering = $0 }
        }
    }
}

private struct NavigationRow: View {
    let title: String
    let systemImage: String
    let value: String?
    let action: () -> Void

    init(_ title: String, systemImage: String, value: String?, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.14), in: Circle())
                Text(title)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .foregroundStyle(Palette.secondaryOnDark)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.tertiaryOnDark)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityValue(Text(value ?? ""))
    }
}

private struct CheckRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, detail: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: 18)
                    .opacity(isSelected ? 1 : 0)
                Text(title)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Palette.secondaryOnDark)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ActionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isEnabled ? Palette.primaryOnDark : Palette.tertiaryOnDark)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

private struct ToggleRow: View {
    let title: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    init(_ title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.title = title
        self.isOn = isOn
        self.onChange = onChange
    }

    /// Label at the leading edge, switch at the trailing edge, as in iOS
    /// Settings. (A Mac switch toggle would otherwise sit beside its label.)
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                // The switch carries the label for VoiceOver.
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle(title, isOn: Binding(get: { isOn }, set: { onChange($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Palette.brandOrange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(Palette.secondaryOnDark)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// "0.3 s later", with − and + to nudge and Reset.
private struct TimingControl: View {
    let title: String
    let value: TimeInterval
    let step: TimeInterval
    let onChange: (TimeInterval) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                Spacer()
                Button("Reset") { onChange(0) }
                    .buttonStyle(.plain)
                    .foregroundStyle(abs(value) < 0.001 ? Palette.tertiaryOnDark : Palette.brandOrange)
                    .disabled(abs(value) < 0.001)
            }
            HStack(spacing: 12) {
                nudge("minus", label: "Earlier") { onChange(rounded(value - step)) }
                Text(description)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText(value: value))
                    .animation(Motion.quick, value: value)
                nudge("plus", label: "Later") { onChange(rounded(value + step)) }
            }
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(description))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(rounded(value + step))
            case .decrement: onChange(rounded(value - step))
            @unknown default: break
            }
        }
    }

    private func nudge(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var description: String {
        if abs(value) < 0.001 { return "In sync" }
        let amount = abs(value).formatted(.number.precision(.fractionLength(0...2)))
        return "\(amount) s \(value > 0 ? "later" : "earlier")"
    }

    private func rounded(_ value: TimeInterval) -> TimeInterval {
        (value * 100).rounded() / 100
    }
}

/// A labelled capsule slider for one picture adjustment.
private struct AdjustmentSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let neutral: Double
    var unit = ""
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Palette.secondaryOnDark)
            }
            CapsuleSlider(
                value: Binding(get: { value }, set: { onChange(snapped($0)) }),
                in: range,
                neutral: neutral,
                label: title
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Sticks to the neutral value when close, so "unchanged" is easy to find.
    private func snapped(_ newValue: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        return abs(newValue - neutral) < span * 0.02 ? neutral : newValue
    }

    private var valueText: String {
        if abs(value - neutral) < 0.0001 { return "Original" }
        if unit.isEmpty {
            return "\(Int((value / max(neutral, 0.0001) * 100).rounded()))%"
        }
        return "\(Int(value.rounded()))\(unit)"
    }
}

/// Subtitles found online for what's playing: in your language first (all
/// languages on request), files made for this exact release at the top.
private struct OnlineSubtitlesPage: View {
    @Environment(PlaybackSession.self) private var session
    @State private var phase = Phase.searching
    @State private var allLanguages = false
    @State private var adding: OnlineSubtitle.ID?
    let onAdded: () -> Void

    enum Phase {
        case searching
        case results([OnlineSubtitle])
        case failed(String)
    }

    private var language: String {
        let preferences = session.controller.trackPreferences
        return preferences.subtitleLanguage ?? session.controller.appLanguage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OptionsGroup {
                ToggleRow("All Languages", isOn: allLanguages) { allLanguages = $0 }
            }
            switch phase {
            case .searching:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Searching\u{2026}")
                        .foregroundStyle(Palette.secondaryOnDark)
                }
                .padding(.horizontal, 6)
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryOnDark)
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            case .results(let subtitles) where subtitles.isEmpty:
                Text("Nothing found\(allLanguages ? "" : " in \(MediaTrack.languageName(for: language) ?? language)"). Try All Languages.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryOnDark)
                    .padding(.horizontal, 6)
            case .results(let subtitles):
                OptionsGroup(footer: "Files marked \u{201C}Made for This File\u{201D} were timed for this exact release.") {
                    ForEach(subtitles.prefix(40)) { subtitle in
                        row(subtitle)
                    }
                }
            }
        }
        .task(id: allLanguages) {
            await search()
        }
    }

    private func row(_ subtitle: OnlineSubtitle) -> some View {
        Button {
            add(subtitle)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(MediaTrack.languageName(for: subtitle.language) ?? subtitle.language)
                        .font(.body.weight(.semibold))
                    Text(subtitle.release)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryOnDark)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    let tags = Self.tags(for: subtitle)
                    if !tags.isEmpty {
                        Text(tags)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(subtitle.matchesFile ? Palette.brandOrange : Palette.tertiaryOnDark)
                    }
                }
                Spacer(minLength: 8)
                if adding == subtitle.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.secondaryOnDark)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(adding != nil)
        .accessibilityHint(Text("Downloads and shows these subtitles"))
    }

    /// "Made for This File · SDH · 12,431 downloads".
    private static func tags(for subtitle: OnlineSubtitle) -> String {
        var tags: [String] = []
        if subtitle.matchesFile { tags.append("Made for This File") }
        if subtitle.isHearingImpaired { tags.append("SDH") }
        if subtitle.isForeignPartsOnly { tags.append("Foreign Parts Only") }
        if subtitle.isMachineTranslated { tags.append("Machine Translated") }
        if subtitle.downloadCount > 0 {
            tags.append("\(subtitle.downloadCount.formatted()) downloads")
        }
        return tags.joined(separator: " \u{00B7} ")
    }

    private func search() async {
        phase = .searching
        do {
            let results = try await session.searchOnlineSubtitles(languages: allLanguages ? [] : [language])
            guard !Task.isCancelled else { return }
            phase = .results(results)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func add(_ subtitle: OnlineSubtitle) {
        adding = subtitle.id
        Task {
            do {
                try await session.addOnlineSubtitle(subtitle)
                session.announce("Subtitles Added")
                adding = nil
                onAdded()
            } catch {
                adding = nil
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

/// − and + around the magnification, and back to the whole picture.
private struct ZoomStepper: View {
    let zoom: VideoZoom
    let onChange: (VideoZoom) -> Void

    var body: some View {
        HStack(spacing: 10) {
            stepButton("Zoom Out", systemImage: "minus.magnifyingglass", isEnabled: zoom.isZoomed) {
                onChange(zoom.stepped(up: false))
            }
            Text(zoom.isZoomed ? zoom.title : "Whole Picture")
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
            stepButton("Zoom In", systemImage: "plus.magnifyingglass", isEnabled: zoom.scale < VideoZoom.maximumScale) {
                onChange(zoom.stepped(up: true))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(Motion.quick, value: zoom.scale)
    }

    private func stepButton(_ title: String, systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 36)
                .background(.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(Text(title))
    }
}

/// Turn left or right, flip either way, and undo it all.
private struct TransformButtons: View {
    let transform: VideoTransform
    let onChange: (VideoTransform) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                button("Turn Left", systemImage: "rotate.left") { onChange(transform.rotated(clockwise: false)) }
                button("Turn Right", systemImage: "rotate.right") { onChange(transform.rotated(clockwise: true)) }
                button("Flip Horizontally", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { onChange(transform.flippedHorizontally()) }
                button("Flip Vertically", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") { onChange(transform.flippedVertically()) }
            }
            .padding(14)
            if !transform.isIdentity {
                Divider().overlay(.white.opacity(0.08))
                ActionRow("Undo \(transform.summary)", systemImage: "arrow.counterclockwise") {
                    onChange(.identity)
                }
            }
        }
    }

    private func button(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 22)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

/// Ten band sliders and the preamp, with their frequencies.
private struct EqualizerBands: View {
    let settings: EqualizerSettings
    let onChange: (EqualizerSettings) -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<EqualizerSettings.bandCount, id: \.self) { index in
                    VStack(spacing: 6) {
                        VerticalCapsuleSlider(
                            value: Binding(
                                get: { Double(settings.bands[index]) },
                                set: { newValue in
                                    var changed = settings
                                    changed.bands[index] = Float(newValue.rounded())
                                    changed.presetName = nil
                                    onChange(changed)
                                }
                            ),
                            in: -20...20,
                            label: "\(EqualizerSettings.frequencyLabel(frequency(index))) band"
                        )
                        .frame(height: 132)
                        Text(shortLabel(frequency(index)))
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.secondaryOnDark)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Preamp")
                    Spacer()
                    Text("\(settings.preamp.formatted(.number.precision(.fractionLength(0)))) dB")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Palette.secondaryOnDark)
                }
                CapsuleSlider(
                    value: Binding(
                        get: { Double(settings.preamp) },
                        set: { newValue in
                            var changed = settings
                            changed.preamp = Float(newValue.rounded())
                            onChange(changed)
                        }
                    ),
                    in: -20...20,
                    neutral: 0,
                    label: "Preamp"
                )
            }
        }
    }

    private func frequency(_ index: Int) -> Float {
        let frequencies = EqualizerPresets.frequencies
        return frequencies.indices.contains(index) ? frequencies[index] : EqualizerSettings.defaultFrequencies[index]
    }

    /// "60", "1k", "16k".
    private func shortLabel(_ hertz: Float) -> String {
        if hertz >= 1_000 {
            return "\((Double(hertz) / 1_000).formatted(.number.precision(.fractionLength(0...1))))k"
        }
        return "\(Int(hertz.rounded()))"
    }
}

/// Type a time ("1:02:03", "45m") and go there.
private struct JumpToTimeField: View {
    let duration: TimeInterval?
    let onJump: (TimeInterval) -> Void
    @State private var text = ""
    @State private var isInvalid = false

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body.monospacedDigit())
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white.opacity(isInvalid ? 0.2 : 0.1), in: Capsule())
                .onSubmit(jump)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
            Button("Go", action: jump)
                .buttonStyle(.plain)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Palette.brandOrange, in: Capsule())
                .disabled(text.isEmpty)
        }
    }

    private var placeholder: String {
        (duration ?? 0) >= 3_600 ? "1:02:03" : "12:34"
    }

    private func jump() {
        guard let seconds = PlaybackTimeFormatter.seconds(from: text) else {
            isInvalid = true
            return
        }
        isInvalid = false
        onJump(min(seconds, duration ?? seconds))
        text = ""
    }
}
