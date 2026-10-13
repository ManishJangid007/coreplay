#if os(macOS)
import DesignSystem
import HomeFeature
import LibraryFeature
import NowPlaying
import PlaybackEngine
import PlayerFeature
import SearchFeature
import SwiftUI

/// The Mac window: a Music-style sidebar (Home, Music, Videos, Library) and a
/// playback bar along the bottom. Video plays in its own window.
struct MacRootView: View {
    enum SidebarItem: Hashable {
        case home
        case search
        case section(LibrarySection)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var selection: SidebarItem? = .home

    var body: some View {
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
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.session.hasItem {
                PlaybackBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.standard, value: model.session.hasItem)
        .dropDestination(for: URL.self) { urls, _ in
            model.open(urls, securityScoped: false)
            return !urls.isEmpty
        }
        .onKeyPress(.space) {
            guard model.session.hasItem else { return .ignored }
            model.session.togglePlayPause()
            return .handled
        }
        .task {
            let openWindow = openWindow
            model.openVideoWindow = { openWindow(id: VideoWindow.id) }
        }
        .onChange(of: model.videoWindowRequest) {
            openWindow(id: VideoWindow.id)
        }
        .alert("Can\u{2019}t Open", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.openErrorMessage ?? "")
        }
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
            showPlayer: { model.presentPlayer(expectingVideo: true) }
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
