#if os(iOS)
import DesignSystem
import HomeFeature
import LibraryFeature
import NowPlaying
import PlaybackEngine
import PlayerFeature
import SearchFeature
import SettingsFeature
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// iPhone and iPad: a tab bar that adapts to a sidebar on iPad, with the mini
/// player in the tab bar's bottom accessory, like Apple Music.
struct PhoneRootView: View {
    enum AppTab: Hashable {
        case home, music, videos, library, search
    }

    @Environment(AppModel.self) private var model
    @Namespace private var playerTransition
    @State private var selectedTab: AppTab = .home

    var body: some View {
        @Bindable var model = model
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab("Music", systemImage: "music.note", value: AppTab.music) {
                NavigationStack {
                    LibraryIndexView(title: "Music", sections: LibrarySection.music)
                }
            }
            Tab("Videos", systemImage: "play.rectangle.on.rectangle", value: AppTab.videos) {
                NavigationStack {
                    LibraryIndexView(title: "Videos", sections: LibrarySection.videos)
                }
            }
            Tab("Library", systemImage: "square.stack", value: AppTab.library) {
                NavigationStack {
                    LibraryIndexView(title: "Library", sections: [.sources, .playlists])
                }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
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
            .navigationTransition(.zoom(sourceID: PlayerTransition.id, in: playerTransition))
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
            // Any file: if VLC can play it, Coreplay should. AppModel.open filters obvious non-media.
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
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
        .environment(\.appActions, actions)
    }

    private var actions: AppActions {
        let model = model
        return AppActions(
            openFiles: { model.isFileImporterPresented = true },
            openSettings: { model.isSettingsPresented = true },
            showPlayer: { model.presentPlayer() }
        )
    }

    /// Video keeps the screen on while it plays.
    private var keepsScreenAwake: Bool {
        model.session.controller.isPlaying && model.session.controller.hasVideo
    }

    private var errorBinding: Binding<Bool> {
        let model = model
        return Binding(
            get: { model.openErrorMessage != nil },
            set: { if !$0 { model.openErrorMessage = nil } }
        )
    }

    /// Every way the player closes (button, Esc, the zoom swipe or pinch):
    /// video pauses, as in the TV app; audio keeps playing.
    private func pauseVideoIfNeeded() {
        if model.session.controller.hasVideo {
            model.session.pause()
        }
    }
}

private enum PlayerTransition {
    static let id = "player"
}
#endif
