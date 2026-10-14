#if os(iOS)
import DesignSystem
import HomeFeature
import LibraryFeature
import MediaLibrary
import MusicFeature
import NowPlaying
import PlaybackEngine
import PlayerFeature
import SearchFeature
import SettingsFeature
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VideoFeature

/// iPhone and iPad: a tab bar that adapts to a sidebar on iPad, with the mini
/// player in the tab bar's bottom accessory, like Apple Music.
struct PhoneRootView: View {
    enum AppTab: Hashable {
        case home, music, videos, library, search
    }

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var playerTransition
    @State private var selectedTab: AppTab = .home

    var body: some View {
        @Bindable var model = model
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack {
                    HomeView()
                        .libraryDestinations()
                }
            }
            Tab("Music", systemImage: "music.note", value: AppTab.music) {
                NavigationStack {
                    MusicLibraryView(extraRows: [
                        .init("Playlists", systemImage: "music.note.list") {
                            LibrarySectionView(section: .playlists)
                        },
                        .init("Composers", systemImage: "music.quarternote.3") {
                            LibrarySectionView(section: .composers)
                        },
                    ])
                    .libraryDestinations()
                }
            }
            Tab("Videos", systemImage: "play.rectangle.on.rectangle", value: AppTab.videos) {
                NavigationStack {
                    VideoLibraryView()
                        .libraryDestinations()
                }
            }
            Tab("Library", systemImage: "square.stack", value: AppTab.library) {
                NavigationStack {
                    LibraryIndexView(title: "Library", sections: [.sources, .playlists])
                        .libraryDestinations()
                }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack {
                    SearchView()
                        .libraryDestinations()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        // Albums and the Music tab start with the hero carousel too.
        .environment(\.libraryHero, .carousels)
        .tabViewBottomAccessory {
            MiniPlayerView()
                .matchedTransitionSource(id: PlayerTransition.id, in: playerTransition)
        }
        .fullScreenCover(isPresented: $model.isPlayerPresented, onDismiss: pauseVideoIfNeeded) {
            PlayerView(onClose: {
                pauseVideoIfNeeded()
                model.isPlayerPresented = false
            })
            .environment(model.session)
            .environment(\.appActions, actions)
            // Logins VLC asks for while a share's video plays.
            .networkPrompts()
            .navigationTransition(.zoom(sourceID: PlayerTransition.id, in: playerTransition))
        }
        .sheet(isPresented: $model.isStreamPanelPresented) {
            OpenStreamView { url in
                // Let the sheet finish closing before the player is presented.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    model.openStream(url)
                }
            }
        }
        .sheet(isPresented: $model.isSettingsPresented) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { model.isSettingsPresented = false }
                        }
                    }
            }
            .environment(model.settings)
            .environment(model.session)
        }
        .fileImporter(
            isPresented: $model.isFileImporterPresented,
            // Files: anything (if VLC can play it, Coreplay should; AppModel.open
            // filters obvious non-media). Folders: added to the library.
            allowedContentTypes: model.importMode == .folder ? [.folder] : [.data],
            allowsMultipleSelection: model.importMode == .files
        ) { result in
            guard case .success(let urls) = result else { return }
            if model.importMode == .folder {
                model.addSources(urls)
                return
            }
            // Let the picker finish dismissing before the player is presented.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                model.open(urls, securityScoped: true)
            }
        }
        .alert("Can\u{2019}t Open", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.openErrorMessage ?? "")
        }
        .onOpenURL { url in
            model.handleOpenURL(url)
        }
        .onChange(of: keepsScreenAwake) { _, keepAwake in
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.library.refreshIfStale()
            }
        }
        .task {
            model.startLibrary()
        }
        .userActivity(AppModel.playbackActivityType, isActive: model.session.hasItem) { activity in
            model.describePlayback(activity)
        }
        .onContinueUserActivity(AppModel.playbackActivityType) { activity in
            model.continuePlayback(activity)
        }
        .networkPrompts()
        .environment(\.appActions, actions)
    }

    private var actions: AppActions {
        let model = model
        return AppActions(
            openFiles: { model.presentFileImporter() },
            openSettings: { model.isSettingsPresented = true },
            showPlayer: { model.presentPlayer() },
            addLibraryFolder: { model.addLibraryFolder() },
            openStream: { model.isStreamPanelPresented = true }
        )
    }

    /// Video keeps the screen on while it plays (not while it floats in
    /// Picture in Picture, when the rest of the phone is in use).
    private var keepsScreenAwake: Bool {
        model.session.controller.isPlaying && model.session.controller.hasVideo && !model.isInPictureInPicture
    }

    private var errorBinding: Binding<Bool> {
        let model = model
        return Binding(
            get: { model.openErrorMessage != nil },
            set: { if !$0 { model.openErrorMessage = nil } }
        )
    }

    /// Every way the player closes (button, Esc, the zoom swipe or pinch):
    /// video pauses, as in the TV app, unless it moved into Picture in
    /// Picture; audio keeps playing.
    private func pauseVideoIfNeeded() {
        if model.session.controller.hasVideo, !model.isInPictureInPicture {
            model.session.pause()
        }
    }
}

private enum PlayerTransition {
    static let id = "player"
}
#endif
