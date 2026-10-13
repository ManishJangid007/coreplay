import AVKit
import DesignSystem
import MediaPlayer
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

/// A scrubber bound to the playback controller.
struct ControllerScrubber: View {
    let controller: PlaybackController
    var appearance: PlaybackScrubber.Appearance = .onDark
    var showsLabels = true

    var body: some View {
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
        .disabled(!controller.isSeekable)
    }
}

/// The system AirPlay / Bluetooth route picker.
#if os(iOS)
struct RoutePickerView: UIViewRepresentable {
    var prioritizesVideoDevices = false

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
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
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif

/// Playback speeds offered in menus. Rates above 2× switch to VLC.
enum PlaybackSpeeds {
    static let common: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    static let extended: [Float] = [3, 4]

    static func label(_ rate: Float) -> String {
        let formatted = rate.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rate)
            : String(format: "%g", rate)
        return "\(formatted)\u{00D7}"
    }
}

/// Audio, subtitle and speed menus: Level 1 controls, as in the TV app.
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
            Label("Audio and Subtitles", systemImage: "captions.bubble")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
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

struct SpeedMenu: View {
    let controller: PlaybackController

    var body: some View {
        Menu {
            Picker("Playback Speed", selection: rateSelection) {
                ForEach(PlaybackSpeeds.common + PlaybackSpeeds.extended, id: \.self) { rate in
                    Text(PlaybackSpeeds.label(rate)).tag(rate)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Playback Speed", systemImage: "speedometer")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
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
