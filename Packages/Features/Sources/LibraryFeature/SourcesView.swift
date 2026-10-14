import DesignSystem
import MediaLibrary
import Networking
import PlaybackEngine
import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Where the library comes from: a settings-style list, not a file browser.
public struct SourcesView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(\.appActions) private var actions
    @Query(sort: \Source.dateAdded) private var sources: [Source]
    @State private var pendingRemoval: Source?
    @State private var isConnecting = false
    @State private var editingServer: SavedServer?
    @State private var connectedPlace: NetworkPlace?

    public init() {}

    public var body: some View {
        List {
            Section {
                ForEach(sources) { source in
                    SourceRow(source: source)
                        .contextMenu { menu(for: source) }
                        #if os(iOS)
                        .swipeActions(edge: .trailing) {
                            if source.kind != .appDocuments {
                                Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                    pendingRemoval = source
                                }
                            }
                        }
                        #endif
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coreplay reads music and videos from these places and keeps them up to date. Your files stay where they are.")
                    if library.activity == .lookingUp {
                        Label("Getting details and artwork\u{2026}", systemImage: "arrow.down.circle")
                    }
                }
            }

            if let error = library.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Dismiss") {
                        library.lastError = nil
                    }
                }
            }

            NetworkSourcesSection(isConnecting: $isConnecting, editing: $editingServer)
        }
        .navigationTitle("Sources")
        .navigationDestination(for: NetworkPlace.self) { place in
            NetworkFolderView(place: place)
        }
        .navigationDestination(item: $connectedPlace) { place in
            NetworkFolderView(place: place)
        }
        .sheet(isPresented: $isConnecting) {
            ConnectToServerView(existing: nil) { server in
                connectedPlace = server.url.map { NetworkPlace(url: $0, title: server.displayName, serverID: server.id) }
            }
        }
        .sheet(item: $editingServer) { server in
            ConnectToServerView(existing: server) { _ in }
        }
        .task {
            // Servers on the network appear while Sources is open (on iOS this
            // is when the local network permission is asked for).
            NetworkDiscovery.shared.start()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Folder\u{2026}", systemImage: "folder.badge.plus") {
                        actions.addLibraryFolder()
                    }
                    #if os(macOS)
                    if !library.hasMusicFolder {
                        Button("Add Music Folder", systemImage: "music.note.house") {
                            library.addMusicFolder()
                        }
                    }
                    if !library.hasMoviesFolder {
                        Button("Add Movies Folder", systemImage: "film") {
                            library.addMoviesFolder()
                        }
                    }
                    #endif
                    Divider()
                    Button("Connect to Server\u{2026}", systemImage: "server.rack") {
                        isConnecting = true
                    }
                    Button("Open Network Stream\u{2026}", systemImage: "antenna.radiowaves.left.and.right") {
                        actions.openStream()
                    }
                    Divider()
                    Button("Check for New Files", systemImage: "arrow.clockwise") {
                        library.scanAll()
                    }
                    .disabled(library.isScanning)
                } label: {
                    Label("Add Source", systemImage: "plus")
                }
            }
        }
        #if os(iOS)
        .refreshable {
            library.scanAll()
        }
        #endif
        .confirmationDialog(
            "Remove \u{201C}\(pendingRemoval?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove from Library", role: .destructive) {
                if let source = pendingRemoval {
                    library.remove(source)
                }
                pendingRemoval = nil
            }
        } message: {
            Text("Its songs and videos leave Coreplay. The files themselves aren\u{2019}t deleted.")
        }
    }

    @ViewBuilder
    private func menu(for source: Source) -> some View {
        Button("Check for New Files", systemImage: "arrow.clockwise") {
            library.rescan(source)
        }
        Picker(selection: Binding(get: { source.videoContent }, set: { library.setVideoContent($0, for: source) })) {
            ForEach(VideoFolderContent.allCases) { content in
                Text(content.title).tag(content)
            }
        } label: {
            Label("Videos in This Folder", systemImage: "film.stack")
        }
        .pickerStyle(.menu)
        #if os(macOS)
        if let url = library.location(of: source) {
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        #endif
        if source.kind != .appDocuments {
            Divider()
            Button("Remove from Library\u{2026}", systemImage: "minus.circle", role: .destructive) {
                pendingRemoval = source
            }
        }
    }
}

private struct SourceRow: View {
    @Environment(LibraryManager.self) private var library
    let source: Source

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(source.isAvailable ? Color.accentColor : Color.secondary)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .font(.body.weight(.medium))
                status
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        if case .scanning(let id, _, let processed, let total) = library.activity, id == source.id {
            VStack(alignment: .leading, spacing: 4) {
                Text(total > 0 ? "Reading \(processed) of \(total) files\u{2026}" : "Looking for files\u{2026}")
                    .foregroundStyle(.secondary)
                if total > 0 {
                    ProgressView(value: Double(processed), total: Double(total))
                        .frame(maxWidth: 240)
                }
            }
        } else if !source.isAvailable {
            Text("Not available \u{2014} connect the drive or add the folder again")
                .foregroundStyle(.red)
        } else {
            Text(summary)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        var parts: [String] = []
        if source.audioFileCount > 0 {
            parts.append(source.audioFileCount == 1 ? "1 song" : "\(source.audioFileCount) songs")
        }
        if source.videoFileCount > 0 {
            parts.append(source.videoFileCount == 1 ? "1 video" : "\(source.videoFileCount) videos")
        }
        if parts.isEmpty {
            parts.append(source.lastScanDate == nil ? "Waiting to be read" : "No music or videos yet")
        }
        if source.videoContent != .automatic {
            parts.append(source.videoContent.title)
        }
        if let lastScan = source.lastScanDate {
            parts.append("updated \(lastScan.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var symbol: String {
        switch source.kind {
        case .appDocuments:
            #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
            #else
            return "internaldrive"
            #endif
        case .folder: return "folder"
        case .file: return "doc"
        case .musicFolder: return "music.note.house"
        case .moviesFolder: return "film"
        }
    }
}
