#if os(macOS)
import DesignSystem
import HomeFeature
import LibraryFeature
import MusicFeature
import NowPlaying
import PlaybackEngine
import PlayerFeature
import SearchFeature
import SwiftUI
import VideoFeature

/// The Mac window: a Music-style sidebar (Home, Music, Videos, Library) and a
/// playback bar along the bottom. Video and Now Playing open over the library
/// in the same window, as in the TV and Music apps.
struct MacRootView: View {
    enum SidebarItem: Hashable {
        case home
        case search
        case section(LibrarySection)
    }

    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .home

    private var showsPlayer: Bool {
        model.isPlayerPresented && model.session.hasItem
    }

    private var videoIsPlaying: Bool {
        model.session.controller.isPlaying && model.session.controller.hasVideo
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                List(selection: $selection) {
                    Label("Search", systemImage: "magnifyingglass")
                        .tag(SidebarItem.search)
                    Label("Home", systemImage: "house")
                        .tag(SidebarItem.home)
                    Section("Music") {
                        ForEach(LibrarySection.music) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(SidebarItem.section(section))
                        }
                    }
                    Section("Videos") {
                        ForEach(LibrarySection.videos) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(SidebarItem.section(section))
                        }
                    }
                    Section("Library") {
                        Label(LibrarySection.sources.title, systemImage: LibrarySection.sources.systemImage)
                            .tag(SidebarItem.section(.sources))
                    }
                }
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
            } detail: {
                NavigationStack {
                    detail
                        .libraryDestinations()
                }
                // A new sidebar item starts a fresh navigation stack.
                .id(selection)
            }
            // Albums starts with the hero carousel too.
            .environment(\.libraryHero, .carousels)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.session.hasItem {
                    PlaybackBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onKeyPress(.space) {
                guard model.session.hasItem else { return .ignored }
                model.session.togglePlayPause()
                return .handled
            }

            if showsPlayer {
                MacPlayerOverlay()
                    .ignoresSafeArea()
                    .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .bottom).combined(with: .opacity)))
                    .zIndex(1)
            }
        }
        .toolbar(showsPlayer ? .hidden : .automatic, for: .windowToolbar)
        .animation(Motion.standard, value: model.session.hasItem)
        .animation(.spring(duration: 0.45, bounce: 0.08), value: showsPlayer)
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDrop(urls)
            return !urls.isEmpty
        }
        .task {
            model.startLibrary()
        }
        .onChange(of: model.session.hasItem) { _, hasItem in
            if !hasItem {
                model.isPlayerPresented = false
            }
        }
        .onChange(of: videoIsPlaying, initial: true) { _, isPlaying in
            model.updateDisplaySleep(videoIsPlaying: isPlaying)
        }
        .alert("Can\u{2019}t Open", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.openErrorMessage ?? "")
        }
        .sheet(isPresented: streamPanelBinding) {
            OpenStreamView { url in
                model.openStream(url)
            }
        }
        // Logins VLC asks for, over the library and the player alike.
        .networkPrompts()
        .environment(\.appActions, actions)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .home, nil:
            HomeView()
        case .search:
            SearchView()
        case .section(let section):
            LibrarySectionView(section: section)
        }
    }

    private var actions: AppActions {
        let model = model
        return AppActions(
            openFiles: { model.presentOpenPanel() },
            openSettings: {},
            showPlayer: { model.presentPlayer() },
            addLibraryFolder: { model.addLibraryFolder() },
            openStream: { model.isStreamPanelPresented = true }
        )
    }

    private var streamPanelBinding: Binding<Bool> {
        let model = model
        return Binding(
            get: { model.isStreamPanelPresented },
            set: { model.isStreamPanelPresented = $0 }
        )
    }

    private var errorBinding: Binding<Bool> {
        let model = model
        return Binding(
            get: { model.openErrorMessage != nil },
            set: { if !$0 { model.openErrorMessage = nil } }
        )
    }
}
#endif
