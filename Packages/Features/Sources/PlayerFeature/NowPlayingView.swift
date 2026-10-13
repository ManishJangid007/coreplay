import DesignSystem
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// Full-screen Now Playing for audio, modelled on Apple Music: an artwork
/// background, large artwork that shrinks when paused, scrubber, transport,
/// volume, AirPlay and the queue.
public struct NowPlayingView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsQueue = false
    @State private var showsOptions = false
    private let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    private var controller: PlaybackController { session.controller }

    public var body: some View {
        GeometryReader { proxy in
            if proxy.size.height < 560 {
                // Short spaces (iPhone landscape, a small Mac window): artwork beside the controls.
                HStack(spacing: 28) {
                    artwork(side: min(proxy.size.height - 32, proxy.size.width * 0.4))
                    VStack(spacing: 10) {
                        header
                        Spacer(minLength: 0)
                        titles
                        ControllerScrubber(controller: controller)
                        transport
                        volume
                        footer
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 12)
                    artwork(side: min(proxy.size.width - 56, proxy.size.height - 420, 560))
                    Spacer(minLength: 12)
                    titles
                        .padding(.bottom, 16)
                    ControllerScrubber(controller: controller)
                        .padding(.bottom, 12)
                    transport
                        .padding(.bottom, 16)
                    volume
                        .padding(.bottom, 20)
                    footer
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Palette.primaryOnDark)
        .background {
            ArtworkBackground(artworkData: controller.metadata.artworkData)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsQueue) {
            UpNextView()
                .environment(session)
        }
        .sheet(isPresented: $showsOptions) {
            PlaybackOptionsView()
                .environment(session)
        }
    }

    // MARK: Pieces

    private func artwork(side: CGFloat) -> some View {
        ArtworkView(
            data: controller.metadata.artworkData,
            shape: .square,
            maxPixelSize: 1_200,
            placeholderSymbol: "music.note"
        )
        .frame(width: max(side, 0), height: max(side, 0))
        .scaleEffect(controller.isPlaying ? 1 : 0.84)
        .artworkShadow(isProminent: controller.isPlaying)
        .animation(Motion.respecting(reduceMotion, Motion.artworkScale), value: controller.isPlaying)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("Close Now Playing"))
            Spacer()
            Button {
                showsOptions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("More"))
        }
        .padding(.top, 8)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(controller.displayTitle)
                .font(.title2.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let subtitle = artistLine {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(Palette.secondaryOnDark)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var artistLine: String? {
        let parts = [controller.displaySubtitle, controller.metadata.albumTitle].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{2014} ")
    }

    private var transport: some View {
        HStack {
            TransportButton("Previous", systemImage: "backward.fill", pointSize: 30) {
                Task { await session.previous() }
            }
            Spacer()
            PlayPauseButton(isPlaying: controller.isPlaying, pointSize: 46) {
                session.togglePlayPause()
            }
            Spacer()
            TransportButton("Next", systemImage: "forward.fill", pointSize: 30) {
                Task { await session.next() }
            }
            .disabled(!session.queue.hasNext)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var volume: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(Palette.secondaryOnDark)
                .accessibilityHidden(true)
            #if os(iOS)
            SystemVolumeSlider()
                .frame(height: 34)
                .accessibilityLabel(Text("Volume"))
            #else
            Slider(value: volumeBinding, in: 0...1)
                .tint(.white)
                .accessibilityLabel(Text("Volume"))
            #endif
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(Palette.secondaryOnDark)
                .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                session.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(session.isShuffled ? Palette.primaryOnDark : Palette.tertiaryOnDark)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(session.isShuffled ? "Shuffle On" : "Shuffle Off"))
            Spacer()
            RoutePickerView()
                .frame(width: 36, height: 36)
                .accessibilityLabel(Text("AirPlay"))
            Spacer()
            Button {
                showsQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Up Next"))
            Spacer()
            Button {
                session.cycleRepeatMode()
            } label: {
                Image(systemName: session.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.title3)
                    .foregroundStyle(session.repeatMode == .off ? Palette.tertiaryOnDark : Palette.primaryOnDark)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(repeatLabel))
        }
        .padding(.horizontal, 12)
    }

    private var repeatLabel: String {
        switch session.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(min(controller.volume, 1)) },
            set: { controller.setVolume(Float($0)) }
        )
    }
}
