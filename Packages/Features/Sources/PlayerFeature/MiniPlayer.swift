import DesignSystem
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// Chooses the full player for the current item: video or Now Playing.
public struct PlayerView: View {
    @Environment(PlaybackSession.self) private var session
    private let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        if session.controller.hasVideo {
            VideoPlayerView(onClose: onClose)
        } else {
            NowPlayingView(onClose: onClose)
        }
    }
}

#if os(iOS)
/// The mini player shown in the tab bar's bottom accessory, like Apple
/// Music. Tapping it opens the full player.
public struct MiniPlayerView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    public init() {}

    private var controller: PlaybackController { session.controller }
    private var hasItem: Bool { controller.currentItem != nil }

    public var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                data: controller.metadata.artworkData,
                shape: .square,
                maxPixelSize: 120,
                placeholderSymbol: controller.hasVideo ? "play.rectangle" : "music.note"
            )
            .frame(width: Metrics.miniPlayerArtworkSize, height: Metrics.miniPlayerArtworkSize)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(hasItem ? controller.displayTitle : "Not Playing")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if placement != .inline, hasItem, let subtitle = controller.displaySubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PlayPauseButton(isPlaying: controller.isPlaying, pointSize: 18) {
                session.togglePlayPause()
            }
            .disabled(!hasItem)

            if placement != .inline {
                TransportButton("Next", systemImage: "forward.fill", pointSize: 16) {
                    Task { await session.next() }
                }
                .disabled(!session.queue.hasNext)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if hasItem {
                actions.showPlayer()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Open Player")) {
            if hasItem {
                actions.showPlayer()
            }
        }
    }
}
#endif

#if os(macOS)
/// The Mac playback bar across the bottom of the main window, like Music:
/// transport, artwork, title, scrubber and volume.
public struct PlaybackBar: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    @State private var showsQueue = false

    public init() {}

    private var controller: PlaybackController { session.controller }

    public var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 4) {
                TransportButton("Previous", systemImage: "backward.fill", pointSize: 15) {
                    Task { await session.previous() }
                }
                PlayPauseButton(isPlaying: controller.isPlaying, pointSize: 20) {
                    session.togglePlayPause()
                }
                TransportButton("Next", systemImage: "forward.fill", pointSize: 15) {
                    Task { await session.next() }
                }
                .disabled(!session.queue.hasNext)
            }

            HStack(spacing: 10) {
                ArtworkView(
                    data: controller.metadata.artworkData,
                    shape: .square,
                    maxPixelSize: 120,
                    placeholderSymbol: controller.hasVideo ? "play.rectangle" : "music.note"
                )
                .frame(width: 40, height: 40)
                .onTapGesture { actions.showPlayer() }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    ControllerScrubber(controller: controller, appearance: .standard, showsLabels: false)
                        .frame(height: 14)
                }
                .frame(minWidth: 220, maxWidth: 520)

                Text(TimeLabels.remaining(controller))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 48, alignment: .trailing)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(value: volumeBinding, in: 0...1)
                    .frame(width: 110)
                    .accessibilityLabel(Text("Volume"))
            }

            RoutePickerView()
                .frame(width: 28, height: 28)
                .accessibilityLabel(Text("AirPlay"))

            if controller.hasVideo {
                Button {
                    actions.showPlayer()
                } label: {
                    Image(systemName: "pip.exit")
                }
                .buttonStyle(.borderless)
                .help("Show Video")
                .accessibilityLabel(Text("Show Video"))
            }

            Button {
                showsQueue.toggle()
            } label: {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(.borderless)
            .help("Up Next")
            .accessibilityLabel(Text("Up Next"))
            .popover(isPresented: $showsQueue, arrowEdge: .top) {
                UpNextView()
                    .environment(session)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(min(controller.volume, 1)) },
            set: { controller.setVolume(Float($0)) }
        )
    }
}
#endif
