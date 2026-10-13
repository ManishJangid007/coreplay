import DesignSystem
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// Full-screen Now Playing for audio, modelled on Apple Music: an artwork
/// background, large artwork that shrinks when paused, scrubber, transport,
/// volume, AirPlay and the queue. On the Mac it fills the main window, with
/// the artwork beside the controls and Up Next as a panel on the right.
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
        content
            .foregroundStyle(Palette.primaryOnDark)
            .background {
                ArtworkBackground(artworkData: controller.metadata.artworkData)
            }
            #if os(iOS)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showsQueue) {
                UpNextView()
                    .environment(session)
            }
            #else
            .environment(\.colorScheme, .dark)
            .focusable()
            .focusEffectDisabled()
            .focused($hasKeyboardFocus)
            .onAppear { hasKeyboardFocus = true }
            .onKeyPress(.escape) {
                onClose()
                return .handled
            }
            .onKeyPress(.space) {
                session.togglePlayPause()
                return .handled
            }
            #endif
            .sheet(isPresented: $showsOptions) {
                PlaybackOptionsView()
                    .environment(session)
            }
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
                    titles(large: false)
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
                            artwork(side: max(min(proxy.size.height - 330, proxy.size.width - 80, 440), 100))
                            controls(large: false)
                                .frame(maxWidth: 440)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 40)
            .padding(.top, 60)
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
                .padding(.horizontal, 20)
                .padding(.top, 34) // clear of the window buttons
        }
        .animation(Motion.respecting(reduceMotion), value: showsQueue)
    }

    private func controls(large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            titles(large: large)
            ControllerScrubber(controller: controller)
            transport
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
            CircleButton(systemImage: "chevron.down", label: "Close Now Playing", action: onClose)
                #if os(macOS)
                .help("Back to Library (Esc)")
                #endif
            Spacer()
            CircleButton(systemImage: "ellipsis", label: "Playback Options") {
                showsOptions = true
            }
            #if os(macOS)
            .help("Playback Options")
            #endif
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
        .accessibilityElement(children: .combine)
    }

    private var artistLine: String? {
        let parts = [controller.displaySubtitle, controller.metadata.albumTitle].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{2014} ")
    }

    private var transport: some View {
        HStack {
            Spacer(minLength: 0)
            TransportButton("Previous", systemImage: "backward.fill", pointSize: 30) {
                Task { await session.previous() }
            }
            Spacer(minLength: 24)
            PlayPauseButton(isPlaying: controller.isPlaying, pointSize: 46) {
                session.togglePlayPause()
            }
            Spacer(minLength: 24)
            TransportButton("Next", systemImage: "forward.fill", pointSize: 30) {
                Task { await session.next() }
            }
            .disabled(!session.queue.hasNext)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 360)
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
            Slider(value: volumeBinding, in: 0...1)
                .controlSize(.small)
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
            FooterButton(
                systemImage: "shuffle",
                label: session.isShuffled ? "Shuffle On" : "Shuffle Off",
                isOn: session.isShuffled
            ) {
                session.toggleShuffle()
            }
            Spacer()
            RoutePickerView()
                .frame(width: 28, height: 28)
                .accessibilityLabel(Text("AirPlay"))
            Spacer()
            FooterButton(systemImage: "list.bullet", label: "Up Next", isOn: showsQueue) {
                showsQueue.toggle()
            }
            Spacer()
            FooterButton(
                systemImage: session.repeatMode == .one ? "repeat.1" : "repeat",
                label: repeatLabel,
                isOn: session.repeatMode != .off
            ) {
                session.cycleRepeatMode()
            }
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

/// A round translucent button for the top corners of Now Playing.
private struct CircleButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(isHovering ? 0.24 : 0.14), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.primaryOnDark)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(label))
    }
}

/// Shuffle, Up Next and Repeat: dim when off, bright with a tint when on.
private struct FooterButton: View {
    let systemImage: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 32, height: 28)
                .background(isOn ? Color.white.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .foregroundStyle(isOn ? Palette.primaryOnDark : Palette.tertiaryOnDark)
                .contentTransition(.symbolEffect(.replace))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
