import AVKit
import DesignSystem
import MediaPlayer
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// Time strings for scrubbers, shared by every player surface.
@MainActor
enum TimeLabels {
    static func elapsed(_ controller: PlaybackController) -> String {
        PlaybackTimeFormatter.string(from: controller.currentTime, referenceDuration: controller.duration)
    }

    static func remaining(_ controller: PlaybackController) -> String {
        guard let duration = controller.duration else { return "LIVE" }
        return PlaybackTimeFormatter.remainingString(currentTime: controller.currentTime, duration: duration)
    }

    static func accessibilityValue(_ controller: PlaybackController) -> String {
        let elapsed = PlaybackTimeFormatter.accessibilityString(from: controller.currentTime)
        guard let duration = controller.duration else { return "\(elapsed), live" }
        return "\(elapsed) of \(PlaybackTimeFormatter.accessibilityString(from: duration))"
    }
}

/// A scrubber bound to the playback controller. Video scrubbers show frame
/// previews and chapter gaps.
struct ControllerScrubber: View {
    let controller: PlaybackController
    var appearance: ControlAppearance = .onDark
    var showsLabels = true
    var showsPreviews = false

    var body: some View {
        Group {
            if showsPreviews {
                PlaybackScrubber(
                    position: controller.currentTime,
                    duration: controller.duration,
                    elapsedText: TimeLabels.elapsed(controller),
                    remainingText: TimeLabels.remaining(controller),
                    accessibilityValue: TimeLabels.accessibilityValue(controller),
                    appearance: appearance,
                    showsLabels: showsLabels,
                    markers: controller.chapters.map(\.start),
                    previewWidth: ScrubPreviewBubble.width,
                    onScrubStart: { controller.beginScrubbing() },
                    onScrub: { controller.scrub(to: $0) },
                    onScrubEnd: { target in
                        Task { await controller.endScrubbing(at: target) }
                    }
                ) { time in
                    ScrubPreviewBubble(controller: controller, time: time)
                }
            } else {
                PlaybackScrubber(
                    position: controller.currentTime,
                    duration: controller.duration,
                    elapsedText: TimeLabels.elapsed(controller),
                    remainingText: TimeLabels.remaining(controller),
                    accessibilityValue: TimeLabels.accessibilityValue(controller),
                    appearance: appearance,
                    showsLabels: showsLabels,
                    onScrubStart: { controller.beginScrubbing() },
                    onScrub: { controller.scrub(to: $0) },
                    onScrubEnd: { target in
                        Task { await controller.endScrubbing(at: target) }
                    }
                )
            }
        }
        .disabled(!controller.isSeekable)
    }
}

/// The frame at the scrub position, with its time and chapter, like YouTube.
/// While the position moves it shows the nearest frame of the strip; once it
/// rests, the exact frame playback will land on. Before any frames are ready
/// it shows just the time.
struct ScrubPreviewBubble: View {
    static var width: CGFloat {
        #if os(macOS)
        232
        #else
        200
        #endif
    }

    let controller: PlaybackController
    let time: TimeInterval

    private var chapterTitle: String? {
        guard controller.chapters.count > 1 else { return nil }
        return controller.chapters.last(where: { $0.start <= time + 0.5 })?.displayTitle
    }

    var body: some View {
        let previews = controller.scrubPreviews
        let _ = previews.revision
        VStack(spacing: 6) {
            if let image = previews.exactImage(at: time) ?? previews.image(at: time) {
                let ratio = image.height > 0 ? CGFloat(image.width) / CGFloat(image.height) : 16.0 / 9.0
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(ratio, contentMode: .fill)
                    .frame(width: Self.width, height: min(Self.width / max(ratio, 0.5), 180))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 4)
            }
            VStack(spacing: 1) {
                if let chapterTitle {
                    Text(chapterTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Text(PlaybackTimeFormatter.string(from: time, referenceDuration: controller.duration))
                    .font(.callout.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
        }
        .frame(width: Self.width)
        .accessibilityHidden(true)
    }
}

/// The system AirPlay / Bluetooth route picker.
#if os(iOS)
struct RoutePickerView: UIViewRepresentable {
    var prioritizesVideoDevices = false

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = prioritizesVideoDevices
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.prioritizesVideoDevices = prioritizesVideoDevices
    }
}

/// The system volume slider (hardware volume buttons move it too).
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
#elseif os(macOS)
struct RoutePickerView: NSViewRepresentable {
    var prioritizesVideoDevices = false

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.white, for: .normal)
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif

/// The AirPlay button sized like the other player buttons.
struct AirPlayButton: View {
    var prioritizesVideoDevices = false

    var body: some View {
        RoutePickerView(prioritizesVideoDevices: prioritizesVideoDevices)
            .frame(width: 26, height: 26)
            .frame(width: Metrics.playerButtonSize, height: Metrics.playerButtonSize)
            .accessibilityLabel(Text("AirPlay"))
            #if os(macOS)
            .help("AirPlay")
            #endif
    }
}

/// Playback speeds offered in menus. Rates above 2× switch to VLC.
enum PlaybackSpeeds {
    static let menu: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4]
    static let all: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4]

    static func label(_ rate: Float) -> String {
        let formatted = rate.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rate)
            : String(format: "%g", rate)
        return "\(formatted)\u{00D7}"
    }

    /// The next speed up or down the list, for keyboard shortcuts.
    static func step(from rate: Float, faster: Bool) -> Float {
        if faster {
            return all.first(where: { $0 > rate + 0.01 }) ?? all.last ?? rate
        }
        return all.last(where: { $0 < rate - 0.01 }) ?? all.first ?? rate
    }
}

/// Audio and subtitle choices: the speech bubble in the TV app's player.
struct AudioAndSubtitlesMenu: View {
    let controller: PlaybackController
    var onAddSubtitleFile: () -> Void

    var body: some View {
        Menu {
            if !controller.audioTracks.isEmpty {
                Picker("Audio", selection: audioSelection) {
                    ForEach(controller.audioTracks) { track in
                        Text(track.displayName()).tag(Optional(track.id))
                    }
                }
                .pickerStyle(.inline)
            }
            Picker("Subtitles", selection: subtitleSelection) {
                Text("Off").tag(String?.none)
                ForEach(controller.subtitleTracks) { track in
                    Text(track.displayName()).tag(Optional(track.id))
                }
            }
            .pickerStyle(.inline)
            Button("Add Subtitle File\u{2026}", systemImage: "doc.badge.plus", action: onAddSubtitleFile)
        } label: {
            PlayerIcon("captions.bubble")
        }
        .playerMenuStyle()
        .accessibilityLabel(Text("Audio and Subtitles"))
        #if os(macOS)
        .help("Audio and Subtitles")
        #endif
    }

    private var audioSelection: Binding<MediaTrack.ID?> {
        Binding(
            get: { controller.audioTracks.first(where: \.isSelected)?.id },
            set: { id in
                if let track = controller.audioTracks.first(where: { $0.id == id }) {
                    controller.selectAudioTrack(track)
                }
            }
        )
    }

    private var subtitleSelection: Binding<MediaTrack.ID?> {
        Binding(
            get: { controller.subtitleTracks.first(where: \.isSelected)?.id },
            set: { id in
                controller.selectSubtitleTrack(controller.subtitleTracks.first(where: { $0.id == id }))
            }
        )
    }
}

/// Playback speed, as in the TV app.
struct SpeedMenu: View {
    let controller: PlaybackController

    var body: some View {
        Menu {
            Picker("Playback Speed", selection: rateSelection) {
                ForEach(PlaybackSpeeds.menu, id: \.self) { rate in
                    Text(PlaybackSpeeds.label(rate)).tag(rate)
                }
            }
            .pickerStyle(.inline)
        } label: {
            PlayerIcon(controller.rate == 1 ? "gauge.with.dots.needle.33percent" : "gauge.with.dots.needle.67percent")
        }
        .playerMenuStyle()
        .accessibilityLabel(Text("Playback Speed"))
        #if os(macOS)
        .help("Playback Speed")
        #endif
    }

    private var rateSelection: Binding<Float> {
        Binding(
            get: { controller.rate },
            set: { rate in
                Task { await controller.setRate(rate) }
            }
        )
    }
}

/// Mute button and volume slider for the Mac player (iPhone and iPad use
/// the hardware buttons).
struct VolumeControl: View {
    let controller: PlaybackController
    var sliderWidth: CGFloat = 84
    @AppStorage(PlaybackPreferences.allowsVolumeBoostKey) private var allowsBoost = false

    /// 100%, or 200% with Settings ▸ Playback ▸ Volume Boost.
    private var maximum: Double {
        allowsBoost ? Double(VolumeLimits.boosted) : Double(VolumeLimits.normal)
    }

    var body: some View {
        HStack(spacing: 2) {
            PlayerIconButton(controller.isMuted ? "Unmute" : "Mute", systemImage: symbol, help: controller.isMuted ? "Unmute (M)" : "Mute (M)") {
                controller.setMuted(!controller.isMuted)
            }
            CapsuleSlider(
                value: Binding(
                    get: { controller.isMuted ? 0 : min(Double(controller.volume), maximum) },
                    set: { newValue in
                        if controller.isMuted { controller.setMuted(false) }
                        setVolume(Float(newValue))
                    }
                ),
                in: 0...maximum,
                label: "Volume",
                step: 0.1
            )
            .frame(width: allowsBoost ? sliderWidth * 1.4 : sliderWidth)
            .help(allowsBoost ? "Volume \(VolumeLimits.percent(controller.volume))" : "Volume")
            .padding(.trailing, 10)
        }
    }

    /// Above 100%, the item moves to VLC, which can boost.
    private func setVolume(_ value: Float) {
        if value > VolumeLimits.normal {
            Task { await controller.setBoostedVolume(value) }
        } else {
            controller.setVolume(value)
        }
    }

    private var symbol: String {
        if controller.isMuted || controller.volume <= 0.001 { return "speaker.slash.fill" }
        if controller.volume < 0.34 { return "speaker.wave.1.fill" }
        if controller.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/// A short confirmation over the player ("Speed 1.5×", "Saved to Pictures").
struct PlayerToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Chromecasts and TVs (DLNA) VLC can send to, as a menu beside AirPlay.
/// It shows only once a device has been found (or while one is playing).
struct CastButton: View {
    var body: some View {
        let casting = CastingCenter.shared
        Group {
            if !casting.targets.isEmpty || casting.isCasting {
                Menu {
                    Section("Play On") {
                        Button {
                            casting.cast(to: nil)
                        } label: {
                            if casting.activeTarget == nil {
                                Label("This Device", systemImage: "checkmark")
                            } else {
                                Text("This Device")
                            }
                        }
                        ForEach(casting.targets) { target in
                            Button {
                                casting.cast(to: target)
                            } label: {
                                if casting.activeTarget == target {
                                    Label(target.name, systemImage: "checkmark")
                                } else {
                                    Label(target.name, systemImage: target.systemImage)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "tv.badge.wifi")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(casting.isCasting ? Color.accentColor : Color.white)
                        .frame(width: Metrics.playerButtonSize, height: Metrics.playerButtonSize)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text(casting.activeTarget.map { "Playing on \($0.name)" } ?? "Cast"))
                #if os(macOS)
                .help(casting.activeTarget.map { "Playing on \($0.name)" } ?? "Play on a TV or Chromecast")
                #endif
                .transition(.scale.combined(with: .opacity))
            }
        }
        .task {
            casting.startSearching()
        }
    }
}

/// Shown instead of the picture while a Chromecast plays it.
struct CastingPlaceholder: View {
    let deviceName: String
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tv.badge.wifi")
                .font(.system(size: 56, weight: .light))
            Text("Playing on \(deviceName)")
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.callout)
                .foregroundStyle(Palette.secondaryOnDark)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}
