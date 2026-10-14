#if os(macOS)
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// The Mac menu bar: File, Playback, Audio, Video and Subtitles, with
/// shortcuts following VLC and QuickTime: ⌘O open, ⌘←/⌘→ previous/next,
/// ⌥⌘←/⌥⌘→ skip 10 s, ⌘↑/⌘↓ volume, ⌥⌘↓ mute, ⌘J jump to a time, ⌥⌘S
/// snapshot. Keys without ⌘ (Space, arrows, F, M, [ ], , . and VLC's
/// G/H/J/K) are handled by the player itself, so they never steal typing
/// from text fields.
struct CoreplayCommands: Commands {
    let model: AppModel

    private var session: PlaybackSession { model.session }
    private var controller: PlaybackController { model.session.controller }
    private var hasItem: Bool { session.hasItem }
    private var hasVideo: Bool { session.hasItem && controller.hasVideo }

    var body: some Commands {
        fileCommands
        playbackMenu
        audioMenu
        videoMenu
        subtitlesMenu
    }

    // MARK: File

    private var fileCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open\u{2026}") {
                model.presentOpenPanel()
            }
            .keyboardShortcut("o")

            Button("Open Network Stream\u{2026}") {
                model.isStreamPanelPresented = true
            }
            .keyboardShortcut("n")

            Button("Add Folder to Library\u{2026}") {
                model.presentFolderPanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Check for New Files") {
                model.library.scanAll()
            }
            .disabled(model.library.isScanning)
        }
    }

    // MARK: Playback

    private var playbackMenu: some Commands {
        CommandMenu("Playback") {
            Button(controller.isPlaying ? "Pause" : "Play") {
                session.togglePlayPause()
            }
            .disabled(!hasItem)

            Button(model.isPlayerPresented ? "Hide Player" : "Show Player") {
                if model.isPlayerPresented {
                    model.dismissPlayer()
                } else {
                    model.presentPlayer()
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(!hasItem)

            Button("Stop") {
                Task { await session.stop() }
            }
            .keyboardShortcut(".")
            .disabled(!hasItem)

            Divider()

            Button("Next") {
                Task { await session.next() }
            }
            .keyboardShortcut(.rightArrow)
            .disabled(!session.queue.hasNext)

            Button("Previous") {
                Task { await session.previous() }
            }
            .keyboardShortcut(.leftArrow)
            .disabled(!hasItem)

            Divider()

            Button("Skip Forward 10 Seconds") {
                Task { await session.skip(by: 10) }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(!hasItem)

            Button("Skip Back 10 Seconds") {
                Task { await session.skip(by: -10) }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(!hasItem)

            Button("Jump to Time\u{2026}") {
                model.presentJumpToTime()
            }
            .keyboardShortcut("j")
            .disabled(!hasItem || !controller.isSeekable)

            if !controller.chapters.isEmpty {
                Menu("Chapters") {
                    ForEach(controller.chapters) { chapter in
                        Button("\(chapter.displayTitle)  \(PlaybackTimeFormatter.string(from: chapter.start, referenceDuration: controller.duration))") {
                            controller.selectChapter(chapter)
                        }
                    }
                }
            }

            if MediaTitle.offersChoice(controller.titles) {
                Menu("Title") {
                    ForEach(MediaTitle.numbered(controller.titles), id: \.title.id) { entry in
                        Toggle(isOn: Binding(
                            get: { controller.currentTitleIndex == entry.title.id },
                            set: { _ in controller.selectTitle(entry.title) }
                        )) {
                            Text([entry.title.displayName(number: entry.number), entry.title.details].compactMap { $0 }.joined(separator: "  "))
                        }
                    }
                }
            }

            if controller.hasDiscMenu {
                // Shift-M in the player, as in VLC.
                Button("Disc Menu") {
                    controller.navigateDisc(.menu)
                }
                .disabled(controller.isShowingDiscMenu)
            }

            Divider()

            Picker("Speed", selection: Binding(
                get: { controller.rate },
                set: { rate in Task { await controller.setRate(rate) } }
            )) {
                ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4], id: \.self) { rate in
                    Text(Self.speedLabel(rate)).tag(rate)
                }
            }
            .disabled(!hasItem)

            Button(loopTitle) {
                controller.advanceABLoop()
            }
            .disabled(!hasItem || !controller.isSeekable)

            Divider()

            Toggle("Shuffle", isOn: Binding(
                get: { session.isShuffled },
                set: { _ in session.toggleShuffle() }
            ))

            Picker("Repeat", selection: Binding(
                get: { session.repeatMode },
                set: { session.repeatMode = $0 }
            )) {
                Text("Off").tag(PlaybackQueue.RepeatMode.off)
                Text("All").tag(PlaybackQueue.RepeatMode.all)
                Text("One").tag(PlaybackQueue.RepeatMode.one)
            }
        }
    }

    private var loopTitle: String {
        switch controller.abLoop.phase {
        case .off: "Set Loop Start"
        case .waitingForEnd: "Set Loop End"
        case .looping: "Stop Looping"
        }
    }

    private static func speedLabel(_ rate: Float) -> String {
        let formatted = rate.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", rate) : String(format: "%g", rate)
        return "\(formatted)\u{00D7}"
    }

    // MARK: Audio

    private var audioMenu: some Commands {
        CommandMenu("Audio") {
            if !controller.audioTracks.isEmpty {
                Picker("Audio Track", selection: Binding(
                    get: { controller.audioTracks.first(where: \.isSelected)?.id },
                    set: { id in
                        if let track = controller.audioTracks.first(where: { $0.id == id }) {
                            controller.selectAudioTrack(track)
                        }
                    }
                )) {
                    ForEach(controller.audioTracks) { track in
                        Text(track.displayName()).tag(Optional(track.id))
                    }
                }
                Divider()
            }

            Button("Volume Up") {
                let target = min(controller.volume + 0.1, PlaybackPreferences.maximumVolume)
                if target > VolumeLimits.normal {
                    Task { await controller.setBoostedVolume(target) }
                } else {
                    controller.setVolume(target)
                }
            }
            .keyboardShortcut(.upArrow)

            Button("Volume Down") {
                controller.setVolume(controller.volume - 0.1)
            }
            .keyboardShortcut(.downArrow)

            Button(controller.isMuted ? "Unmute" : "Mute") {
                controller.setMuted(!controller.isMuted)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Divider()

            Button("Audio Earlier") {
                Task { await controller.setAudioDelay(Self.nudged(controller.audioDelay, by: -0.05)) }
            }
            .disabled(!hasItem)
            Button("Audio Later") {
                Task { await controller.setAudioDelay(Self.nudged(controller.audioDelay, by: 0.05)) }
            }
            .disabled(!hasItem)
            Button("Reset Audio Timing") {
                Task { await controller.setAudioDelay(0) }
            }
            .disabled(controller.audioDelay == 0)

            Divider()

            Picker("Channels", selection: Binding(
                get: { controller.stereoMode },
                set: { mode in Task { await controller.setStereoMode(mode) } }
            )) {
                ForEach(StereoMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Toggle("Equalizer", isOn: Binding(
                get: { controller.equalizer.isEnabled },
                set: { isOn in
                    var settings = controller.equalizer
                    settings.isEnabled = isOn
                    Task { await session.setEqualizer(settings) }
                }
            ))
        }
    }

    private static func nudged(_ value: TimeInterval, by amount: TimeInterval) -> TimeInterval {
        ((value + amount) * 100).rounded() / 100
    }

    // MARK: Video

    private var videoMenu: some Commands {
        CommandMenu("Video") {
            Picker("Size", selection: Binding(
                get: { controller.fillMode },
                set: { controller.setFillMode($0) }
            )) {
                ForEach(VideoFillMode.allCases, id: \.self) { mode in
                    Text(mode == .fit ? "Fit to Window" : "Fill Window").tag(mode)
                }
            }
            .disabled(!hasVideo)

            Picker("Shape", selection: Binding(
                get: { controller.aspectRatio },
                set: { ratio in Task { await controller.setAspectRatio(ratio) } }
            )) {
                Text("Original").tag(VideoRatio?.none)
                ForEach(VideoRatio.aspectPresets) { ratio in
                    Text(ratio.title).tag(Optional(ratio))
                }
            }
            .disabled(!hasVideo)

            Picker("Crop", selection: Binding(
                get: { controller.cropRatio },
                set: { ratio in Task { await controller.setCropRatio(ratio) } }
            )) {
                Text("None").tag(VideoRatio?.none)
                ForEach(VideoRatio.cropPresets) { ratio in
                    Text(ratio.title).tag(Optional(ratio))
                }
            }
            .disabled(!hasVideo)

            Picker("Deinterlacing", selection: Binding(
                get: { controller.deinterlace },
                set: { mode in Task { await controller.setDeinterlace(mode) } }
            )) {
                ForEach(DeinterlaceMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .disabled(!hasVideo)

            Picker("Deinterlacing Method", selection: Binding(
                get: { controller.deinterlaceFilter },
                set: { filter in Task { await controller.setDeinterlaceFilter(filter) } }
            )) {
                ForEach(DeinterlaceFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .disabled(!hasVideo || controller.deinterlace == .off)

            Divider()

            Button("Zoom In") {
                controller.setZoom(controller.zoom.stepped(up: true))
            }
            .keyboardShortcut("=")
            .disabled(!hasVideo || controller.isSpherical || controller.zoom.scale >= VideoZoom.maximumScale)

            Button("Zoom Out") {
                controller.setZoom(controller.zoom.stepped(up: false))
            }
            .keyboardShortcut("-")
            .disabled(!hasVideo || !controller.zoom.isZoomed)

            Button("Whole Picture") {
                controller.setZoom(.none)
            }
            .keyboardShortcut("0")
            .disabled(!controller.zoom.isZoomed)

            Menu("Turn and Flip") {
                Button("Turn Left") {
                    controller.rotate(clockwise: false)
                }
                .keyboardShortcut("l")
                Button("Turn Right") {
                    controller.rotate(clockwise: true)
                }
                .keyboardShortcut("r")
                Button("Flip Horizontally") {
                    controller.flipHorizontally()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Flip Vertically") {
                    controller.flipVertically()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                Divider()
                Button("Undo Turn and Flip") {
                    controller.setTransform(.identity)
                }
                .disabled(controller.transform.isIdentity)
            }
            .disabled(!hasVideo || controller.isSpherical)

            if controller.isSpherical {
                Button("Look Straight Ahead") {
                    controller.setViewpoint(.straightAhead)
                }
                .disabled(controller.viewpoint.isStraightAhead)
            }

            Button("Reset Colours") {
                Task { await controller.setVideoAdjustments(.neutral) }
            }
            .disabled(controller.videoAdjustments.isNeutral)

            Divider()

            Button("Next Frame") {
                controller.stepFrame(forward: true)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
            .disabled(!hasVideo)

            Button("Previous Frame") {
                controller.stepFrame(forward: false)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
            .disabled(!hasVideo)

            Button("Save Picture to Pictures Folder") {
                model.saveSnapshot()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(!hasVideo)

            Divider()

            Button(controller.pictureInPicture.isActive ? "Exit Picture in Picture" : "Enter Picture in Picture") {
                controller.pictureInPicture.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .control])
            .disabled(!controller.pictureInPicture.isPossible && !controller.pictureInPicture.isActive)

            Toggle("Float on Top", isOn: Binding(
                get: { model.isFloatingOnTop },
                set: { model.setFloatingOnTop($0) }
            ))
        }
    }

    // MARK: Subtitles

    private var subtitlesMenu: some Commands {
        CommandMenu("Subtitles") {
            Picker("Subtitles", selection: Binding(
                get: { controller.subtitleTracks.first(where: \.isSelected)?.id },
                set: { id in
                    controller.selectSubtitleTrack(controller.subtitleTracks.first(where: { $0.id == id }))
                }
            )) {
                Text("Off").tag(String?.none)
                ForEach(controller.subtitleTracks) { track in
                    Text(track.displayName()).tag(Optional(track.id))
                }
            }
            .pickerStyle(.inline)
            .disabled(!hasVideo)

            Button("Add Subtitle File\u{2026}") {
                model.presentSubtitlePanel()
            }
            .disabled(!hasVideo)

            Divider()

            Button("Subtitles Earlier") {
                Task { await controller.setSubtitleDelay(Self.nudged(controller.subtitleDelay, by: -0.1)) }
            }
            .disabled(!hasVideo)
            Button("Subtitles Later") {
                Task { await controller.setSubtitleDelay(Self.nudged(controller.subtitleDelay, by: 0.1)) }
            }
            .disabled(!hasVideo)
            Button("Reset Subtitle Timing") {
                Task { await controller.setSubtitleDelay(0) }
            }
            .disabled(controller.subtitleDelay == 0)

            Divider()

            Picker("Text Size", selection: Binding(
                get: { controller.subtitleSize },
                set: { size in Task { await session.setSubtitleSize(size) } }
            )) {
                ForEach(SubtitleSize.allCases, id: \.self) { size in
                    Text(size.title).tag(size)
                }
            }
        }
    }
}
#endif
