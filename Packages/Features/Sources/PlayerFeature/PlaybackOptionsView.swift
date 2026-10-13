import DesignSystem
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// Level 2 options behind the player's "…" button: tracks, speed, timing,
/// chapters, the playback engine and media info. Plain-language labels only
/// ("Subtitle timing", never "SPU delay").
public struct PlaybackOptionsView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    private let onAddSubtitleFile: (() -> Void)?

    /// - Parameter onAddSubtitleFile: Called (and the sheet dismissed) when the
    ///   user asks to add a subtitle file. The presenter shows the file
    ///   picker once the sheet is gone. Omit it to hide the button.
    public init(onAddSubtitleFile: (() -> Void)? = nil) {
        self.onAddSubtitleFile = onAddSubtitleFile
    }

    private var controller: PlaybackController { session.controller }

    public var body: some View {
        NavigationStack {
            Form {
                tracksSection
                speedSection
                timingSection
                if !controller.chapters.isEmpty {
                    chaptersSection
                }
                engineSection
                mediaInfoSection
            }
            .formStyle(.grouped)
            .navigationTitle("Playback Options")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    // MARK: Sections

    private var tracksSection: some View {
        Section("Audio and Subtitles") {
            if !controller.audioTracks.isEmpty {
                Picker("Audio", selection: audioSelection) {
                    ForEach(controller.audioTracks) { track in
                        Text(track.displayName()).tag(Optional(track.id))
                    }
                }
            }
            Picker("Subtitles", selection: subtitleSelection) {
                Text("Off").tag(String?.none)
                ForEach(controller.subtitleTracks) { track in
                    Text(track.displayName()).tag(Optional(track.id))
                }
            }
            if let onAddSubtitleFile {
                Button("Add Subtitle File\u{2026}") {
                    onAddSubtitleFile()
                    dismiss()
                }
            }
        }
    }

    private var speedSection: some View {
        Section {
            Picker("Speed", selection: rateSelection) {
                ForEach(PlaybackSpeeds.common + PlaybackSpeeds.extended, id: \.self) { rate in
                    Text(PlaybackSpeeds.label(rate)).tag(rate)
                }
            }
        } footer: {
            Text("Speech keeps its natural pitch at every speed.")
        }
    }

    private var timingSection: some View {
        Section {
            TimingStepper(
                title: "Subtitle Timing",
                value: controller.subtitleDelay,
                step: 0.1,
                laterDescription: "later",
                earlierDescription: "earlier"
            ) { newValue in
                Task { await controller.setSubtitleDelay(newValue) }
            }
            TimingStepper(
                title: "Audio Timing",
                value: controller.audioDelay,
                step: 0.05,
                laterDescription: "later",
                earlierDescription: "earlier"
            ) { newValue in
                Task { await controller.setAudioDelay(newValue) }
            }
        } header: {
            Text("Timing")
        } footer: {
            if !controller.capabilities.contains(.subtitleDelay) {
                Text("Changing timing moves this video to the VLC engine at the same position.")
            }
        }
    }

    private var chaptersSection: some View {
        Section("Chapters") {
            ForEach(controller.chapters) { chapter in
                Button {
                    controller.selectChapter(chapter)
                    dismiss()
                } label: {
                    HStack {
                        Text(chapter.displayTitle)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(PlaybackTimeFormatter.string(from: chapter.start, referenceDuration: controller.duration))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var engineSection: some View {
        Section {
            LabeledContent("Playing With", value: controller.activeEngine?.displayName ?? "\u{2014}")
            if let reason = controller.routingReason {
                LabeledContent("Why", value: reason.explanation)
            }
            if let engine = controller.activeEngine {
                let other: EngineKind = engine == .vlc ? .avFoundation : .vlc
                Button("Switch to \(other.displayName)") {
                    Task { await controller.switchEngine(to: other) }
                }
            }
        } header: {
            Text("Playback Engine")
        } footer: {
            Text("Coreplay picks AVFoundation when Apple supports every track, and VLC for everything else.")
        }
    }

    private var mediaInfoSection: some View {
        Section("Media Info") {
            if let dimensions = controller.videoDimensions {
                LabeledContent("Resolution", value: "\(dimensions.width) \u{00D7} \(dimensions.height) (\(dimensions.resolutionBadge))")
            }
            if let duration = controller.duration {
                LabeledContent("Duration", value: PlaybackTimeFormatter.string(from: duration))
            }
            if let audio = controller.audioTracks.first(where: \.isSelected) {
                LabeledContent("Audio", value: [audio.codec, MediaTrack.channelLayoutName(audio.channelCount)].compactMap { $0 }.joined(separator: ", ").nonEmptyOr("\u{2014}"))
            }
            if let url = controller.currentItem?.url {
                LabeledContent("File", value: url.isFileURL ? url.lastPathComponent : url.absoluteString)
            }
        }
    }

    // MARK: Bindings

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

    private var rateSelection: Binding<Float> {
        Binding(
            get: { controller.rate },
            set: { rate in Task { await controller.setRate(rate) } }
        )
    }
}

/// A stepper for audio/subtitle offsets that reads "0.3 s later" rather than "+300 ms".
private struct TimingStepper: View {
    let title: String
    let value: TimeInterval
    let step: TimeInterval
    let laterDescription: String
    let earlierDescription: String
    let onChange: (TimeInterval) -> Void

    var body: some View {
        Stepper {
            LabeledContent(title, value: description)
        } onIncrement: {
            onChange(rounded(value + step))
        } onDecrement: {
            onChange(rounded(value - step))
        }
        .contextMenu {
            Button("Reset") { onChange(0) }
        }
    }

    private var description: String {
        if abs(value) < 0.001 { return "In sync" }
        let amount = abs(value).formatted(.number.precision(.fractionLength(0...2)))
        return "\(amount) s \(value > 0 ? laterDescription : earlierDescription)"
    }

    private func rounded(_ value: TimeInterval) -> TimeInterval {
        (value * 100).rounded() / 100
    }
}

private extension String {
    func nonEmptyOr(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
