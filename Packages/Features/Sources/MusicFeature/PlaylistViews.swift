import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Your playlists as tiles: ones you make, smart ones that fill themselves,
/// and ones imported from M3U, PLS or XSPF files.
public struct PlaylistsView: View {
    @Environment(LibraryManager.self) private var library
    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @State private var smartEditor: SmartEditorTarget?
    @State private var isNaming = false
    @State private var newName = ""
    @State private var isImporting = false
    @State private var importMessage: String?

    public init() {}

    public var body: some View {
        Group {
            if playlists.isEmpty {
                ContentUnavailableView {
                    Label("No Playlists", systemImage: "music.note.list")
                } description: {
                    Text("Make a playlist, let a smart playlist fill itself, or import an M3U, PLS or XSPF file.")
                } actions: {
                    Button("New Playlist") { startNaming() }
                        .buttonStyle(.borderedProminent)
                    Button("New Smart Playlist") { smartEditor = .new }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20)], spacing: 26) {
                        ForEach(playlists) { playlist in
                            NavigationLink(value: playlist) {
                                PlaylistTile(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                                    library.delete(playlist)
                                }
                            }
                        }
                    }
                    .padding(Metrics.contentPadding)
                }
            }
        }
        .navigationTitle("Playlists")
        .navigationDestination(for: Playlist.self) { playlist in
            PlaylistDetailView(playlist: playlist)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Playlist", systemImage: "music.note.list") { startNaming() }
                    Button("New Smart Playlist\u{2026}", systemImage: "gearshape") { smartEditor = .new }
                    Divider()
                    Button("Import Playlist\u{2026}", systemImage: "square.and.arrow.down") { isImporting = true }
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }
            }
        }
        .alert("New Playlist", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Create") { library.makePlaylist(named: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $smartEditor) { target in
            SmartPlaylistEditor(target: target)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.playlistTypes) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let imported = try library.importPlaylist(from: url)
                if imported.missing > 0 {
                    importMessage = "\(imported.missing) of the songs it lists aren\u{2019}t in your library, so \u{201C}\(imported.playlist.name)\u{201D} has the rest."
                }
            } catch {
                importMessage = "Coreplay couldn\u{2019}t read \u{201C}\(url.lastPathComponent)\u{201D}."
            }
        }
        .alert("Playlist Imported", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func startNaming() {
        newName = ""
        isNaming = true
    }

    static var playlistTypes: [UTType] {
        [UTType.m3uPlaylist, UTType.playlist] + ["m3u8", "pls", "xspf"].compactMap { UTType(filenameExtension: $0) }
    }
}

/// A playlist as a tile: a mosaic of its covers (a smart playlist's gear on
/// colour), its name and what kind it is.
struct PlaylistTile: View {
    @Environment(LibraryManager.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let playlist: Playlist
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaylistArtwork(playlist: playlist)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(isHovering ? 0.3 : 0.15), radius: isHovering ? 12 : 6, y: 4)
                .scaleEffect(isHovering && !reduceMotion ? 1.03 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(playlist.isSmart ? "Smart Playlist" : (playlist.itemKeys.count == 1 ? "1 song" : "\(playlist.itemKeys.count) songs"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(Motion.quick, value: isHovering)
        .accessibilityElement(children: .combine)
    }
}

struct PlaylistArtwork: View {
    @Environment(LibraryManager.self) private var library
    let playlist: Playlist

    var body: some View {
        let keys = library.artworkKeys(for: playlist)
        if playlist.isSmart || keys.isEmpty {
            let colors = GenreTile.colors(for: playlist.name)
            LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    Image(systemName: playlist.isSmart ? "gearshape.2.fill" : "music.note.list")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
        } else if keys.count < 4 {
            ArtworkView(url: library.artworkURL(keys[0], .grid), shape: .square, maxPixelSize: 500, placeholderSymbol: "music.note")
        } else {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    cover(keys[0])
                    cover(keys[1])
                }
                GridRow {
                    cover(keys[2])
                    cover(keys[3])
                }
            }
        }
    }

    private func cover(_ key: String) -> some View {
        ArtworkView(url: library.artworkURL(key, .grid), shape: .square, maxPixelSize: 300, placeholderSymbol: "music.note")
            .clipShape(Rectangle())
    }
}

/// A playlist: its songs as chart rows, with Play and Shuffle. Regular
/// playlists reorder and remove; smart ones edit their rules.
struct PlaylistDetailView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var items: [PlaylistItem] = []
    @State private var missing = 0
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isEditingRules = false
    @State private var confirmsDelete = false
    @State private var editingTrack: Track?

    var body: some View {
        let playback = MusicPlayback(library: library, session: session)
        let tracks = items.map(\.track)
        List {
            header(tracks: tracks, playback: playback)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    playback.play(tracks, startingAt: item.track)
                } label: {
                    ChartTrackRow(track: item.track, number: index + 1, isCurrent: playback.isCurrent(item.track), isStriped: index.isMultiple(of: 2))
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                .disabled(!item.track.isAvailable)
                .contextMenu {
                    TrackMenuItems(tracks: [item.track], onEditInfo: { editingTrack = item.track })
                    if !playlist.isSmart {
                        Divider()
                        Button("Remove from Playlist", systemImage: "minus.circle", role: .destructive) {
                            library.removeItems(at: [item.position], from: playlist)
                            reload()
                        }
                    }
                }
            }
            .onDelete(perform: playlist.isSmart ? nil : { offsets in
                library.removeItems(at: IndexSet(offsets.map { items[$0].position }), from: playlist)
                reload()
            })
            .onMove(perform: playlist.isSmart ? nil : { source, destination in
                let target = destination < items.count ? items[destination].position : playlist.itemKeys.count
                library.moveItems(in: playlist, from: IndexSet(source.map { items[$0].position }), to: target)
                reload()
            })
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if playlist.isSmart {
                        Button("Edit Rules\u{2026}", systemImage: "gearshape") { isEditingRules = true }
                    }
                    Button("Rename\u{2026}", systemImage: "pencil") {
                        newName = playlist.name
                        isRenaming = true
                    }
                    Divider()
                    Button("Delete Playlist\u{2026}", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                } label: {
                    Label("Playlist Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Playlist", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") { library.rename(playlist, to: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \u{201C}\(playlist.name)\u{201D}?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) {
                library.delete(playlist)
                dismiss()
            }
        } message: {
            Text("The songs stay in your library.")
        }
        .sheet(isPresented: $isEditingRules, onDismiss: reload) {
            SmartPlaylistEditor(target: .existing(playlist))
        }
        .sheet(item: $editingTrack) { track in
            TrackEditView(track: track)
        }
        .task(id: library.revision) {
            reload()
        }
    }

    private func reload() {
        guard playlist.modelContext != nil else { return }
        items = library.items(in: playlist)
        missing = library.missingCount(in: playlist)
    }

    private func header(tracks: [Track], playback: MusicPlayback) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            PlaylistArtwork(playlist: playlist)
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .artworkShadow()
            VStack(alignment: .leading, spacing: 8) {
                Text(playlist.isSmart ? "SMART PLAYLIST" : "PLAYLIST")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(playlist.name)
                    .font(.system(size: 34, weight: .heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(MusicFormat.summary(songs: tracks.count, seconds: tracks.reduce(0) { $0 + ($1.duration ?? 0) }))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                if missing > 0 {
                    Label(missing == 1 ? "1 song isn\u{2019}t in this library" : "\(missing) songs aren\u{2019}t in this library", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                PlayShuffleButtons(
                    onPlay: { playback.play(tracks, shuffled: false) },
                    onShuffle: { playback.shuffle(tracks) }
                )
                .frame(maxWidth: 320)
                .disabled(tracks.isEmpty)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

/// Which smart playlist the editor shows.
enum SmartEditorTarget: Identifiable {
    case new
    case existing(Playlist)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let playlist): playlist.id.uuidString
        }
    }
}

/// A smart playlist's name and rules: match all or any, each rule a field,
/// a comparison and a value, then how many songs and in what order.
struct SmartPlaylistEditor: View {
    @Environment(LibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    let target: SmartEditorTarget
    @State private var name = ""
    @State private var rules = SmartPlaylistRules(rules: [.init(field: .genre, comparison: .contains, value: "")])
    @State private var isLimited = false
    @State private var limit = 25
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Smart Playlist"))
                }
                Section {
                    Picker("Songs Matching", selection: $rules.matchesAll) {
                        Text("All of These").tag(true)
                        Text("Any of These").tag(false)
                    }
                    ForEach($rules.rules) { $rule in
                        RuleRow(rule: $rule)
                    }
                    .onDelete { rules.rules.remove(atOffsets: $0) }
                    Button("Add Rule", systemImage: "plus.circle") {
                        rules.rules.append(.init(field: .artist, comparison: .contains, value: ""))
                    }
                } header: {
                    Text("Rules")
                } footer: {
                    Text("Dates count days back from today.")
                }
                Section {
                    Toggle("Limit", isOn: $isLimited)
                    if isLimited {
                        Stepper("\(limit) songs", value: $limit, in: 1...2_000, step: limit < 50 ? 5 : 25)
                    }
                    Picker("Order", selection: $rules.order) {
                        ForEach(SmartPlaylistRules.Order.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                }
                Section("Start From") {
                    Button("Recently Added") { use(.recentlyAdded, name: "Recently Added") }
                    Button("Most Played") { use(.mostPlayed, name: "Most Played") }
                    Button("Never Played") { use(.neverPlayed, name: "Never Played") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Smart Playlist" : "Edit Smart Playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save", action: save)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520)
        #endif
        .onAppear(perform: load)
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard case .existing(let playlist) = target, let saved = playlist.rules else { return }
        name = playlist.name
        rules = saved
        isLimited = saved.limit != nil
        limit = saved.limit ?? 25
    }

    private func use(_ preset: SmartPlaylistRules, name presetName: String) {
        rules = preset
        isLimited = preset.limit != nil
        limit = preset.limit ?? 25
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = presetName
        }
    }

    private func save() {
        var final = rules
        final.limit = isLimited ? limit : nil
        final.rules.removeAll { $0.field.kind != .text && $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        switch target {
        case .new:
            library.makePlaylist(named: name.isEmpty ? "Smart Playlist" : name, rules: final)
        case .existing(let playlist):
            library.setRules(final, for: playlist)
            if !name.trimmingCharacters(in: .whitespaces).isEmpty, name != playlist.name {
                library.rename(playlist, to: name)
            }
        }
        dismiss()
    }
}

private struct RuleRow: View {
    @Binding var rule: SmartPlaylistRules.Rule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Field", selection: $rule.field) {
                    ForEach(SmartPlaylistRules.Field.allCases) { field in
                        Text(field.title).tag(field)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Picker("Comparison", selection: $rule.comparison) {
                    ForEach(SmartPlaylistRules.Comparison.options(for: rule.field.kind)) { comparison in
                        Text(comparison.title).tag(comparison)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            TextField(placeholder, text: $rule.value)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(rule.field.kind == .text ? .default : .numberPad)
                #endif
        }
        .onChange(of: rule.field) { _, field in
            let options = SmartPlaylistRules.Comparison.options(for: field.kind)
            if !options.contains(rule.comparison) {
                rule.comparison = options[0]
            }
        }
    }

    private var placeholder: String {
        switch rule.field.kind {
        case .text: "Text"
        case .number: rule.field == .duration ? "Minutes" : "Number"
        case .date: "Days"
        }
    }
}

/// Add to Playlist, in a song's menu: a new playlist, or one you made.
struct AddToPlaylistMenu: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    let tracks: [Track]

    var body: some View {
        Menu("Add to Playlist", systemImage: "text.badge.plus") {
            Button("New Playlist", systemImage: "plus") {
                let name = tracks.count == 1 ? tracks[0].albumTitle : "New Playlist"
                let playlist = library.makePlaylist(named: name.isEmpty ? "New Playlist" : name, tracks: tracks)
                session.announce("Added to \u{201C}\(playlist.name)\u{201D}")
            }
            let playlists = library.playlists().filter { !$0.isSmart }
            if !playlists.isEmpty {
                Divider()
            }
            ForEach(playlists) { playlist in
                Button(playlist.name) {
                    library.add(tracks, to: playlist)
                    session.announce("Added to \u{201C}\(playlist.name)\u{201D}")
                }
            }
        }
    }
}

// MARK: - Composers

/// Composers from the songs' tags, each with their songs.
public struct ComposersView: View {
    @Query(sort: \Track.sortTitle) private var tracks: [Track]

    public init() {}

    public var body: some View {
        let byComposer = Dictionary(grouping: tracks.filter { !($0.composer ?? "").trimmingCharacters(in: .whitespaces).isEmpty }) {
            $0.composer!.trimmingCharacters(in: .whitespaces)
        }
        let names = byComposer.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        Group {
            if names.isEmpty {
                ContentUnavailableView("No Composers", systemImage: "music.quarternote.3", description: Text("Composers come from your songs\u{2019} tags."))
            } else {
                List(names, id: \.self) { name in
                    NavigationLink {
                        ComposerDetailView(name: name, tracks: byComposer[name] ?? [])
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "music.quarternote.3")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                Text(GenreTile.songCount(byComposer[name]?.count ?? 0))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Composers")
    }
}

private struct ComposerDetailView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    let name: String
    let tracks: [Track]

    var body: some View {
        let playback = MusicPlayback(library: library, session: session)
        List {
            PlayShuffleButtons(
                onPlay: { playback.play(tracks, shuffled: false) },
                onShuffle: { playback.shuffle(tracks) }
            )
            .frame(maxWidth: 320)
            .listRowSeparator(.hidden)
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    playback.play(tracks, startingAt: track)
                } label: {
                    ChartTrackRow(track: track, isCurrent: playback.isCurrent(track), isStriped: index.isMultiple(of: 2))
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                .contextMenu {
                    TrackMenuItems(tracks: [track])
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(name)
    }
}
