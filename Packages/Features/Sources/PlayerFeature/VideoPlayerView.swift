import DesignSystem
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// The video player: chrome-free by default; tap (or move the pointer) to
/// reveal title, scrubber, transport and the audio/subtitle/speed menus.
/// Controls hide after three seconds of playback.
public struct VideoPlayerView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showsOptions = false
    @State private var importsSubtitleAfterOptions = false
    @State private var isImportingSubtitle = false
    @State private var subtitleError: String?
    @FocusState private var hasKeyboardFocus: Bool

    private let onClose: () -> Void

    /// - Parameter onClose: Dismisses the player (iOS) or closes the window (macOS).
    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    private var controller: PlaybackController { session.controller }

    private var isLoading: Bool {
        controller.state == .opening || controller.state == .buffering
    }

    public var body: some View {
        ZStack {
            Palette.playerBackground.ignoresSafeArea()

            VideoSurface(controller: controller)
                .ignoresSafeArea()

            statusOverlay

            if controlsVisible {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            hasKeyboardFocus = true
            toggleControls()
        }
        #if os(macOS)
        .onContinuousHover { phase in
            if case .active = phase {
                showControls()
            }
        }
        #endif
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .defaultFocus($hasKeyboardFocus, true)
        .onKeyPress(phases: .down) { press in
            handleKey(press)
        }
        .onAppear {
            hasKeyboardFocus = true
            scheduleAutoHide()
        }
        .onDisappear {
            hideTask?.cancel()
        }
        .onChange(of: controller.isPlaying) { _, isPlaying in
            if isPlaying {
                scheduleAutoHide()
            } else {
                showControls(autoHide: false)
            }
        }
        .onChange(of: controller.isScrubbing) { _, isScrubbing in
            if isScrubbing {
                hideTask?.cancel()
            } else {
                scheduleAutoHide()
            }
        }
        .preferredColorScheme(.dark)
        #if os(iOS)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        #endif
        .sheet(isPresented: $showsOptions, onDismiss: optionsDismissed) {
            PlaybackOptionsView(onAddSubtitleFile: { importsSubtitleAfterOptions = true })
                .environment(session)
        }
        .fileImporter(isPresented: $isImportingSubtitle, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            Task {
                do {
                    try await controller.addExternalSubtitle(url: url)
                } catch {
                    subtitleError = error.localizedDescription
                }
            }
        }
        .alert("Couldn\u{2019}t Add Subtitles", isPresented: Binding(get: { subtitleError != nil }, set: { if !$0 { subtitleError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(subtitleError ?? "")
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var statusOverlay: some View {
        if let error = controller.state.error {
            ContentUnavailableView {
                Label("Can\u{2019}t Play", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                Button("Close", action: onClose)
                    .buttonStyle(.glass)
            }
            .foregroundStyle(.white)
        } else if isLoading, !controlsVisible {
            // With controls visible the spinner takes the play button's place instead.
            loadingIndicator
        }
    }

    private var loadingIndicator: some View {
        ProgressView()
            .controlSize(.large)
            .tint(.white)
            .frame(width: 70, height: 70)
            .accessibilityLabel(Text("Loading"))
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            centerTransport
            Spacer(minLength: 0)
            bottomBar
        }
        .foregroundStyle(.white)
        .background {
            VStack {
                LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            #if os(iOS)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("Close"))
            #endif

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle = controller.displaySubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryOnDark)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)

            RoutePickerView(prioritizesVideoDevices: true)
                .frame(width: 32, height: 32)
                .accessibilityLabel(Text("AirPlay"))

            Button {
                hideTask?.cancel()
                showsOptions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("Playback Options"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var centerTransport: some View {
        HStack(spacing: 44) {
            TransportButton("Back 10 Seconds", systemImage: "gobackward.10", pointSize: 28) {
                Task { await controller.skip(by: -10) }
                scheduleAutoHide()
            }
            if isLoading {
                loadingIndicator
            } else {
                PlayPauseButton(isPlaying: controller.isPlaying, pointSize: 44) {
                    session.togglePlayPause()
                    scheduleAutoHide()
                }
            }
            TransportButton("Forward 10 Seconds", systemImage: "goforward.10", pointSize: 28) {
                Task { await controller.skip(by: 10) }
                scheduleAutoHide()
            }
        }
        .disabled(controller.currentItem == nil)
        // The error view sits in the middle of the screen; keep the transport out of its way.
        .opacity(controller.state.error == nil ? 1 : 0)
        .allowsHitTesting(controller.state.error == nil)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            ControllerScrubber(controller: controller)
            HStack(spacing: 20) {
                if let dimensions = controller.videoDimensions {
                    Text(dimensions.resolutionBadge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.secondaryOnDark, lineWidth: 1))
                        .foregroundStyle(Palette.secondaryOnDark)
                        .accessibilityLabel(Text("Resolution \(dimensions.resolutionBadge)"))
                }
                Spacer()
                SpeedMenu(controller: controller)
                AudioAndSubtitlesMenu(controller: controller) {
                    hideTask?.cancel()
                    isImportingSubtitle = true
                }
            }
            .font(.title3)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        // Interacting with the bar (menus included) keeps the controls up a little longer.
        .simultaneousGesture(TapGesture().onEnded { scheduleAutoHide() })
    }

    // MARK: - Behaviour

    private func close() {
        hideTask?.cancel()
        onClose()
    }

    private func optionsDismissed() {
        if importsSubtitleAfterOptions {
            importsSubtitleAfterOptions = false
            isImportingSubtitle = true
        } else {
            scheduleAutoHide()
        }
    }

    private func toggleControls() {
        if controlsVisible, controller.isPlaying {
            withAnimation(Motion.respecting(reduceMotion, Motion.controlsFade)) {
                controlsVisible = false
            }
        } else {
            showControls()
        }
    }

    private func showControls(autoHide: Bool = true) {
        if !controlsVisible {
            withAnimation(Motion.respecting(reduceMotion, Motion.controlsFade)) {
                controlsVisible = true
            }
        }
        if autoHide {
            scheduleAutoHide()
        } else {
            hideTask?.cancel()
        }
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, controller.isPlaying, !controller.isScrubbing,
                  !showsOptions, !isImportingSubtitle else { return }
            withAnimation(Motion.respecting(reduceMotion, Motion.controlsFade)) {
                controlsVisible = false
            }
        }
    }

    /// Space plays/pauses, ←/→ skip 10 s. On the Mac, ↑/↓ change volume, F
    /// toggles full screen and Esc leaves full screen before closing.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .space:
            session.togglePlayPause()
        case .leftArrow:
            Task { await controller.skip(by: -10) }
        case .rightArrow:
            Task { await controller.skip(by: 10) }
        #if os(macOS)
        case .upArrow:
            controller.setVolume(controller.volume + 0.1)
        case .downArrow:
            controller.setVolume(controller.volume - 0.1)
        #endif
        case .escape:
            #if os(macOS)
            if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                return .handled
            }
            #endif
            close()
            return .handled
        default:
            #if os(macOS)
            if press.characters.lowercased() == "f" {
                NSApp.keyWindow?.toggleFullScreen(nil)
                return .handled
            }
            #endif
            return .ignored
        }
        showControls()
        return .handled
    }
}
