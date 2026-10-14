import DesignSystem
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// Full-screen Now Playing for audio, modelled on Apple Music on iOS 26: an
/// artwork background, large artwork that shrinks when paused, the title,
/// scrubber, plain transport symbols, volume, and a row of round buttons
/// for shuffle, AirPlay, Up Next and repeat. On the Mac it fills the main
/// window, with the artwork beside the controls and Up Next as a panel on
/// the right. Playback options open in a panel over it.
public struct NowPlayingView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsQueue = false
    @State private var showsOptions = false
    #if os(macOS)
    @FocusState private var hasKeyboardFocus: Bool
    #endif
    private let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    private var controller: PlaybackController { session.controller }

    public var body: some View {
        ZStack {
            content
                .foregroundStyle(Palette.primaryOnDark)

            if showsOptions {
                PlayerOptionsLayer(isVideo: false, topInset: topInset, onClose: { showsOptions = false })
                    .background {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .onTapGesture { showsOptions = false }
                    }
            }
        }
        .background {
            ArtworkBackground(artworkData: controller.metadata.artworkData)
        }
        .animation(Motion.respecting(reduceMotion), value: showsOptions)
        #if os(iOS)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsQueue) {
            UpNextView()
                .environment(session)
                .presentationDetents([.medium, .large])
        }
        #else
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onAppear { hasKeyboardFocus = true }
        .onKeyPress(.escape) {
            if showsOptions {
                showsOptions = false
            } else {
                onClose()
            }
            return .handled
        }
        .onKeyPress(.space) {
            session.togglePlayPause()
            return .handled
        }
        #endif
    }

    private var topInset: CGFloat {
        #if os(macOS)
        34
        #else
        8
        #endif
    }

    // MARK: Layouts

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macLayout
        #else
        phoneLayout
        #endif
    }

    #if os(iOS)
    private var phoneLayout: some View {
        GeometryReader { proxy in
            if proxy.size.height < 560 {
                // Short spaces (iPhone landscape): artwork beside the controls.
                HStack(spacing: 28) {
                    artwork(side: min(proxy.size.height - 32, proxy.size.width * 0.4))
                    VStack(spacing: 10) {
                        header
                        Spacer(minLength: 0)
                        titles(large: false)
                        ControllerScrubber(controller: controller)
                        transport(compact: true)
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
                    titles(large: false)
                        .padding(.bottom, 16)
                    ControllerScrubber(controller: controller)
                        .padding(.bottom, 10)
                    transport(compact: false)
                        .padding(.bottom, 14)
                    volume
                        .padding(.bottom, 18)
                    footer
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
    }
    #endif

    #if os(macOS)
    private var macLayout: some View {
        HStack(spacing: 0) {
            GeometryReader { proxy in
                let wide = proxy.size.width > 720
                Group {
                    if wide {
                        HStack(spacing: 56) {
                            artwork(side: max(min(proxy.size.height - 150, proxy.size.width * 0.45, 600), 120))
                            controls(large: true)
                                .frame(maxWidth: 440)
                        }
                    } else {
                        VStack(spacing: 22) {
                            // Leaves room for the controls at full size (about 340 points).
                            artwork(side: max(min(proxy.size.height - 362, proxy.size.width - 80, 440), 100))
                            controls(large: false)
                                .frame(maxWidth: 440)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 40)
            .padding(.top, 70)
            .padding(.bottom, 32)

            if showsQueue {
                UpNextView()
                    .environment(session)
                    .frame(width: 320)
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .trailing))
            }
        }
        .overlay(alignment: .top) {
            header
                .padding(.horizontal, 18)
                .padding(.top, topInset)
        }
        .animation(Motion.respecting(reduceMotion), value: showsQueue)
    }

    private func controls(large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            titles(large: large)
            ControllerScrubber(controller: controller)
            transport(compact: false)
            volume
            footer
        }
    }
    #endif

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
            GlassIconButton("Close Now Playing", systemImage: "chevron.down", help: "Back to Library (Esc)", action: onClose)
            Spacer()
            GlassIconButton("Playback Options", systemImage: "ellipsis", help: "Speed, Equalizer and More") {
                showsOptions = true
            }
        }
        #if os(iOS)
        .padding(.top, 8)
        #endif
    }

    private func titles(large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(controller.displayTitle)
                .font(large ? .largeTitle.weight(.bold) : .title2.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let subtitle = artistLine {
                Text(subtitle)
                    .font(large ? .title2 : .title3)
                    .foregroundStyle(Palette.secondaryOnDark)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Never squeezed: a tight layout would otherwise shrink the title below the artist line.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var artistLine: String? {
        let parts = [controller.displaySubtitle, controller.metadata.albumTitle].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{2014} ")
    }

    /// Plain symbols, as in Apple Music: no circles, no boxes.
    private func transport(compact: Bool) -> some View {
        HStack {
            Spacer(minLength: 0)
            TransportButton("Previous", systemImage: "backward.fill", pointSize: compact ? 26 : 32) {
                Task { await session.previous() }
            }
            Spacer(minLength: 20)
            PlayPauseButton(isPlaying: controller.isPlaying, pointSize: compact ? 38 : 48) {
                session.togglePlayPause()
            }
            Spacer(minLength: 20)
            TransportButton("Next", systemImage: "forward.fill", pointSize: compact ? 26 : 32) {
                Task { await session.next() }
            }
            .disabled(!session.queue.hasNext)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
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
            CapsuleSlider(value: volumeBinding, in: 0...1, label: "Volume", step: 0.1)
            #endif
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(Palette.secondaryOnDark)
                .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        HStack {
            NowPlayingRoundButton(
                systemImage: "shuffle",
                label: session.isShuffled ? "Shuffle On" : "Shuffle Off",
                isOn: session.isShuffled
            ) {
                session.toggleShuffle()
            }
            Spacer()
            AirPlayButton()
            CastButton()
            Spacer()
            NowPlayingRoundButton(systemImage: "list.bullet", label: "Up Next", isOn: showsQueue) {
                showsQueue.toggle()
            }
            Spacer()
            NowPlayingRoundButton(
                systemImage: session.repeatMode == .one ? "repeat.1" : "repeat",
                label: repeatLabel,
                isOn: session.repeatMode != .off
            ) {
                session.cycleRepeatMode()
            }
        }
        .padding(.horizontal, 8)
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

/// Shuffle, Up Next and Repeat: a dim symbol when off; bright, on a soft
/// glass circle, when on.
private struct NowPlayingRoundButton: View {
    let systemImage: String
    let label: String
    let isOn: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            PlayerIcon(systemImage)
                .foregroundStyle(isOn || isHovering ? Palette.primaryOnDark : Palette.secondaryOnDark)
                .glassEffect(isOn ? .regular.tint(.white.opacity(0.18)) : .identity, in: .circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        #if os(macOS)
        .help(label)
        #endif
    }
}
