import DesignSystem
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// The video player, in the style of the TV app on iOS 26: chrome-free by
/// default; tap (or move the pointer) to show round glass buttons along the
/// top, plain transport in the middle, and the title, scrubber (with frame
/// previews) and audio, speed and options buttons along the bottom. Controls
/// hide after three seconds of playback. Every other option opens in a panel
/// over the video, so nothing leaves the player.
public struct VideoPlayerView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showsOptions = false
    @State private var isImportingSubtitle = false
    @State private var errorMessage: String?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var pinchScale: CGFloat = 1
    /// The item whose Up Next card was dismissed ("Watch Credits").
    @State private var dismissedUpNextFor: UUID?
    /// The item the Up Next card already moved on from.
    @State private var advancedFrom: UUID?
    @AppStorage(PlaybackPreferences.autoplaysNextEpisodeKey) private var autoplaysNextEpisode = true
    @FocusState private var hasKeyboardFocus: Bool

    private let onClose: () -> Void

    /// - Parameter onClose: Dismisses the player and returns to the library.
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
                .scaleEffect(pinchScale)

            if controller.isExternalPlaybackActive {
                externalPlaybackPlaceholder
            }

            statusOverlay

            if controlsVisible, !showsOptions {
                controlsOverlay
                    .transition(.opacity)
            }

            if !showsOptions, let offer = upNextOffer {
                UpNextCard(item: offer.item, countdown: offer.countdown, onPlay: playNextNow, onDismiss: dismissUpNext)
                    .padding(.horizontal, 24)
                    .padding(.bottom, controlsVisible ? 150 : 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if showsOptions {
                optionsLayer
            }

            if let toast {
                PlayerToast(message: toast)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, topInset + 56)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            hasKeyboardFocus = true
            if showsOptions {
                closeOptions()
            } else {
                toggleControls()
            }
        }
        #if os(iOS)
        .gesture(pinchGesture)
        #endif
        #if os(macOS)
        .onContinuousHover { phase in
            if case .active = phase, !showsOptions {
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
            toastTask?.cancel()
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
        .onChange(of: session.announcement) { _, announcement in
            if let announcement {
                showToast(announcement.message)
            }
        }
        // At the end of the last video, go back to where it was started from.
        .onChange(of: controller.state) { _, state in
            if state == .ended, controller.hasVideo, !session.queue.hasNext {
                close()
            }
        }
        // The countdown at the end credits ran out: on to the next episode.
        .onChange(of: upNextPhase == .startNext) { _, shouldStart in
            if shouldStart {
                playNextNow()
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.standard), value: upNextOffer != nil)
        .animation(Motion.respecting(reduceMotion, Motion.standard), value: showsOptions)
        .animation(Motion.respecting(reduceMotion, Motion.quick), value: toast)
        #if os(iOS)
        .preferredColorScheme(.dark)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        #else
        .environment(\.colorScheme, .dark)
        #endif
        .fileImporter(isPresented: $isImportingSubtitle, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            Task {
                do {
                    try await controller.addExternalSubtitle(url: url)
                    showToast("Subtitles Added")
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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
        } else if isLoading, !controlsVisible || showsOptions {
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

    private var externalPlaybackPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "airplayvideo")
                .font(.system(size: 56, weight: .light))
            Text("Playing on AirPlay")
                .font(.title3.weight(.semibold))
            Text(controller.displayTitle)
                .font(.callout)
                .foregroundStyle(Palette.secondaryOnDark)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
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
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 240)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    /// Clear of the window's close, minimise and zoom buttons on the Mac.
    private var topInset: CGFloat {
        #if os(macOS)
        34
        #else
        8
        #endif
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            GlassIconButton(closeTitle, systemImage: closeSymbol, help: "Back to Library (Esc)", action: close)

            if controller.pictureInPicture.isPossible {
                GlassIconButton("Picture in Picture", systemImage: "pip.enter", help: "Picture in Picture (P)") {
                    controller.pictureInPicture.start()
                }
                .transition(.scale.combined(with: .opacity))
            }

            Spacer(minLength: 12)

            GlassControlGroup {
                AirPlayButton(prioritizesVideoDevices: true)
                #if os(macOS)
                VolumeControl(controller: controller)
                PlayerIconButton("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right", help: "Full Screen (F)") {
                    toggleFullScreen()
                }
                #endif
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, topInset)
        .animation(Motion.quick, value: controller.pictureInPicture.isPossible)
    }

    private var closeTitle: String {
        #if os(macOS)
        "Back to Library"
        #else
        "Close"
        #endif
    }

    private var closeSymbol: String {
        #if os(macOS)
        "chevron.backward"
        #else
        "xmark"
        #endif
    }

    private var centerTransport: some View {
        HStack(spacing: 52) {
            TransportButton("Back 10 Seconds", systemImage: "gobackward.10", pointSize: 30) {
                Task { await controller.skip(by: -10) }
                scheduleAutoHide()
            }
            ZStack {
                if isLoading {
                    loadingIndicator
                } else {
                    PlayPauseButton(isPlaying: controller.isPlaying, pointSize: 46) {
                        session.togglePlayPause()
                        scheduleAutoHide()
                    }
                }
            }
            .frame(width: 80, height: 80)
            TransportButton("Forward 10 Seconds", systemImage: "goforward.10", pointSize: 30) {
                Task { await controller.skip(by: 10) }
                scheduleAutoHide()
            }
        }
        .overVideoShadow()
        .disabled(controller.currentItem == nil)
        // The error view sits in the middle of the screen; keep the transport out of its way.
        .opacity(controller.state.error == nil ? 1 : 0)
        .allowsHitTesting(controller.state.error == nil)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 16) {
                titleBlock
                Spacer(minLength: 12)
                GlassControlGroup {
                    if controller.abLoop.phase != .off {
                        PlayerIconButton("Stop Looping", systemImage: "repeat.circle.fill", help: "A\u{2013}B Loop (Shift-L)") {
                            controller.clearABLoop()
                            showToast("Loop Off")
                        }
                    }
                    SpeedMenu(controller: controller)
                    AudioAndSubtitlesMenu(controller: controller) {
                        hideTask?.cancel()
                        isImportingSubtitle = true
                    }
                    PlayerIconButton("More Options", systemImage: "ellipsis", help: "Picture, Sound, Chapters and More") {
                        openOptions()
                    }
                }
            }
            ControllerScrubber(controller: controller, showsPreviews: true)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        // Interacting with the bar (menus included) keeps the controls up a little longer.
        .simultaneousGesture(TapGesture().onEnded { scheduleAutoHide() })
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(controller.displayTitle)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 8) {
                if let subtitle = controller.displaySubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .lineLimit(1)
                }
                if let dimensions = controller.videoDimensions {
                    Text(dimensions.resolutionBadge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.secondaryOnDark, lineWidth: 1))
                        .accessibilityLabel(Text("Resolution \(dimensions.resolutionBadge)"))
                }
            }
            .font(.subheadline)
            .foregroundStyle(Palette.secondaryOnDark)
        }
        .overVideoShadow()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Up Next

    private struct UpNextOffer {
        let item: PlaybackItem
        let countdown: UpNextPolicy.Countdown?
    }

    /// Where the player is in the end-credits countdown (see `UpNextPolicy`).
    private var upNextPhase: UpNextPolicy.Phase {
        guard controller.hasVideo, !controller.isScrubbing, controller.state.error == nil,
              let current = controller.currentItem, dismissedUpNextFor != current.id, advancedFrom != current.id,
              let next = session.upNext.first, next.kind == .video else { return .hidden }
        let credits = UpNextPolicy.creditsStart(chapters: controller.chapters, duration: controller.duration)
        return UpNextPolicy.phase(
            currentTime: controller.currentTime,
            duration: controller.duration,
            creditsStart: credits,
            autoplays: autoplaysNextEpisode
        )
    }

    private var upNextOffer: UpNextOffer? {
        guard let next = session.upNext.first else { return nil }
        switch upNextPhase {
        case .hidden:
            return nil
        case .offering(let countdown):
            return UpNextOffer(item: next, countdown: countdown)
        case .startNext:
            return UpNextOffer(item: next, countdown: UpNextPolicy.Countdown(remaining: 0, total: UpNextPolicy.countdown))
        }
    }

    private func playNextNow() {
        guard let current = controller.currentItem, advancedFrom != current.id else { return }
        advancedFrom = current.id
        Task { await session.next() }
    }

    private func dismissUpNext() {
        dismissedUpNextFor = controller.currentItem?.id
    }

    // MARK: - Options panel

    private var optionsLayer: some View {
        PlayerOptionsLayer(
            isVideo: true,
            topInset: topInset,
            onClose: closeOptions,
            onAddSubtitleFile: {
                closeOptions()
                isImportingSubtitle = true
            },
            onSnapshot: saveSnapshot
        )
    }

    private func openOptions() {
        hideTask?.cancel()
        showsOptions = true
    }

    private func closeOptions() {
        showsOptions = false
        hasKeyboardFocus = true
        showControls()
    }

    // MARK: - Behaviour

    private func close() {
        hideTask?.cancel()
        onClose()
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

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    private func toggleFullScreen() {
        #if os(macOS)
        NSApp.keyWindow?.toggleFullScreen(nil)
        #endif
    }

    private func saveSnapshot() {
        Task {
            do {
                let destination = try await SnapshotSaver.save(controller)
                showToast("Saved to \(destination)")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    #if os(iOS)
    /// Pinch out to fill the screen, in to fit, as in the TV app.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                pinchScale = min(max(value.magnification, 0.85), 1.2)
            }
            .onEnded { value in
                withAnimation(Motion.quick) { pinchScale = 1 }
                if value.magnification > 1.08, controller.fillMode != .fill {
                    controller.setFillMode(.fill)
                    showToast("Fill")
                } else if value.magnification < 0.93, controller.fillMode != .fit {
                    controller.setFillMode(.fit)
                    showToast("Fit")
                }
            }
    }
    #endif

    // MARK: - Keyboard

    /// Space plays and pauses, ←/→ skip 10 s (⌥ for a minute), F toggles
    /// full screen and Esc steps back (panel, full screen, then the player).
    /// VLC's keys work too: [ ] and = for speed, , and . for frames, M mute,
    /// B and V cycle audio and subtitles, G/H subtitle timing, J/K audio
    /// timing, Shift-L the A–B loop, Shift-S a snapshot, P Picture in Picture.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let skip: TimeInterval = press.modifiers.contains(.option) ? 60 : 10
        switch press.key {
        case .space:
            session.togglePlayPause()
        case .leftArrow:
            Task { await controller.skip(by: -skip) }
        case .rightArrow:
            Task { await controller.skip(by: skip) }
        #if os(macOS)
        case .upArrow:
            controller.setVolume(controller.volume + 0.1)
            showToast("Volume \(Int((controller.volume * 100).rounded()))%")
        case .downArrow:
            controller.setVolume(controller.volume - 0.1)
            showToast("Volume \(Int((controller.volume * 100).rounded()))%")
        #endif
        case .escape:
            if showsOptions {
                closeOptions()
                return .handled
            }
            #if os(macOS)
            if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                return .handled
            }
            #endif
            close()
            return .handled
        default:
            return handleCharacter(press)
        }
        showControls()
        return .handled
    }

    private func handleCharacter(_ press: KeyPress) -> KeyPress.Result {
        let shift = press.modifiers.contains(.shift)
        guard !press.modifiers.contains(.command) else { return .ignored }
        switch press.characters.lowercased() {
        case "f":
            toggleFullScreen()
        case "m":
            controller.setMuted(!controller.isMuted)
            showToast(controller.isMuted ? "Muted" : "Sound On")
        case "]", "+":
            changeSpeed(faster: true)
        case "[", "-":
            changeSpeed(faster: false)
        case "=":
            Task { await controller.setRate(1) }
            showToast("Speed 1\u{00D7}")
        case ".":
            controller.stepFrame(forward: true)
        case ",":
            controller.stepFrame(forward: false)
        case "b":
            cycleAudio()
        case "v":
            cycleSubtitles()
        case "g":
            nudgeSubtitles(by: -0.05)
        case "h":
            nudgeSubtitles(by: 0.05)
        case "j":
            nudgeAudio(by: -0.05)
        case "k":
            nudgeAudio(by: 0.05)
        case "l" where shift:
            controller.advanceABLoop()
            switch controller.abLoop.phase {
            case .off: showToast("Loop Off")
            case .waitingForEnd: showToast("Loop Start Set")
            case .looping: showToast("Looping")
            }
        case "s" where shift:
            saveSnapshot()
        case "p":
            controller.pictureInPicture.toggle()
        case "i":
            openOptions()
        default:
            return .ignored
        }
        return .handled
    }

    private func changeSpeed(faster: Bool) {
        let rate = PlaybackSpeeds.step(from: controller.rate, faster: faster)
        Task { await controller.setRate(rate) }
        showToast("Speed \(PlaybackSpeeds.label(rate))")
    }

    private func cycleAudio() {
        let tracks = controller.audioTracks
        guard tracks.count > 1 else { return }
        let current = tracks.firstIndex(where: \.isSelected) ?? -1
        let next = tracks[(current + 1) % tracks.count]
        controller.selectAudioTrack(next)
        showToast("Audio: \(next.displayName())")
    }

    private func cycleSubtitles() {
        let tracks = controller.subtitleTracks
        guard !tracks.isEmpty else {
            showToast("No Subtitles")
            return
        }
        let current = tracks.firstIndex(where: \.isSelected)
        let nextIndex = current.map { $0 + 1 } ?? 0
        if nextIndex >= tracks.count {
            controller.selectSubtitleTrack(nil)
            showToast("Subtitles Off")
        } else {
            controller.selectSubtitleTrack(tracks[nextIndex])
            showToast("Subtitles: \(tracks[nextIndex].displayName())")
        }
    }

    private func nudgeSubtitles(by amount: TimeInterval) {
        let value = ((controller.subtitleDelay + amount) * 100).rounded() / 100
        Task { await controller.setSubtitleDelay(value) }
        showToast("Subtitles \(Self.timing(value))")
    }

    private func nudgeAudio(by amount: TimeInterval) {
        let value = ((controller.audioDelay + amount) * 100).rounded() / 100
        Task { await controller.setAudioDelay(value) }
        showToast("Audio \(Self.timing(value))")
    }

    private static func timing(_ value: TimeInterval) -> String {
        if abs(value) < 0.001 { return "in sync" }
        let amount = abs(value).formatted(.number.precision(.fractionLength(0...2)))
        return "\(amount) s \(value > 0 ? "later" : "earlier")"
    }
}
