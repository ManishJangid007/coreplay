import DesignSystem
import MediaLibrary
import PhotosUI
import PlaybackCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Edit Info

/// Edit Info for a video: what it is, its title and year, and for episodes
/// the show, season and episode. Edits survive rescans and lookups.
struct VideoInfoEditor: View {
    @Environment(LibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    private let video: Video
    @State private var edit: VideoEdit

    init(video: Video) {
        self.video = video
        _edit = State(initialValue: VideoEdit(video: video))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $edit.kind) {
                        ForEach(VideoKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    TextField("Title", text: $edit.title)
                    TextField("Year", value: $edit.year, format: .number.grouping(.never))
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                } footer: {
                    if edit.kind != video.kind, edit.kind != .homeVideo {
                        Text("Coreplay will look it up again as a \(edit.kind.title.lowercased()).")
                    }
                }
                if edit.kind == .episode {
                    Section("Episode") {
                        TextField("Show", text: $edit.showTitle)
                        TextField("Season", value: $edit.seasonNumber, format: .number.grouping(.never))
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        TextField("Episode", value: $edit.episodeNumber, format: .number.grouping(.never))
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }
                Section("Summary") {
                    TextField("Summary", text: $edit.overview, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Info")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        library.apply(edit, to: video)
                        dismiss()
                    }
                    .disabled(edit == VideoEdit(video: video))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
    }
}

/// Edit Info for a show.
struct ShowInfoEditor: View {
    @Environment(LibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    private let show: TVShow
    @State private var edit: ShowEdit

    init(show: TVShow) {
        self.show = show
        _edit = State(initialValue: ShowEdit(show: show))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $edit.title)
                    TextField("Year", value: $edit.year, format: .number.grouping(.never))
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                Section("Summary") {
                    TextField("Summary", text: $edit.overview, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Info")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        library.apply(edit, to: show)
                        dismiss()
                    }
                    .disabled(edit == ShowEdit(show: show) || edit.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 320)
        #endif
    }
}

// MARK: - Fix Match

/// Searches TMDB (or, without a key, Wikipedia for movies and TVmaze for
/// shows) and lets the user pick the right movie or show.
struct FixMatchView: View {
    enum Target {
        case video(Video)
        case show(TVShow)

        var isShow: Bool {
            if case .show = self { return true }
            return false
        }
    }

    @Environment(LibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    let target: Target
    @State private var query = ""
    @State private var year: Int?
    @State private var results: [LookupResult] = []
    @State private var isSearching = false
    @State private var applying: Int?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(target.isShow ? "Show Title" : "Movie Title", text: $query)
                        .onSubmit { Task { await search() } }
                    TextField("Year (optional)", value: $year, format: .number.grouping(.never))
                        .onSubmit { Task { await search() } }
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Button("Search \(library.lookupSourceName(forShows: target.isShow))") {
                        Task { await search() }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching || !library.canLookUp)
                } footer: {
                    if !library.canLookUp {
                        Text("Turn on Look Up Without a Key, or add your TMDB API key, in Settings \u{25B8} Metadata.")
                    } else if !library.hasMetadataKey {
                        Text("Searching \(library.lookupSourceName(forShows: target.isShow)), which needs no key. A TMDB key in Settings \u{25B8} Metadata gives larger artwork.")
                    }
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if results.isEmpty, !query.isEmpty {
                        Text("No results. Try a shorter title, or leave out the year.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { result in
                        Button {
                            Task { await choose(result) }
                        } label: {
                            LookupResultRow(result: result, isApplying: applying == result.id)
                        }
                        .buttonStyle(.plain)
                        .disabled(applying != nil)
                    }
                }
            }
            .navigationTitle("Fix Match")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                switch target {
                case .video(let video):
                    query = video.title.isEmpty ? video.displayTitle : video.title
                    year = video.year
                case .show(let show):
                    query = show.title
                    year = show.year
                }
                await search()
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, library.canLookUp else { return }
        isSearching = true
        problem = nil
        defer { isSearching = false }
        do {
            results = target.isShow
                ? try await library.searchShows(text, year: year)
                : try await library.searchMovies(text, year: year)
            if results.isEmpty, year != nil {
                results = target.isShow
                    ? try await library.searchShows(text, year: nil)
                    : try await library.searchMovies(text, year: nil)
            }
        } catch {
            problem = error.localizedDescription
        }
    }

    private func choose(_ result: LookupResult) async {
        applying = result.id
        defer { applying = nil }
        do {
            switch target {
            case .video(let video):
                try await library.fixMatch(video, with: result)
            case .show(let show):
                try await library.fixMatch(show, with: result)
            }
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}

private struct LookupResultRow: View {
    let result: LookupResult
    let isApplying: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(url: result.posterURL, shape: .poster, maxPixelSize: 200, placeholderSymbol: "film")
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.title)
                        .font(.headline)
                    if let year = result.year {
                        Text(String(year))
                            .foregroundStyle(.secondary)
                    }
                }
                if let overview = result.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if isApplying {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Choose Artwork

/// Pick a frame from the video, or an image, as artwork; or go back to the
/// automatic artwork.
struct ArtworkPickerView: View {
    enum Target {
        case video(Video)
        case show(TVShow)
    }

    enum Mode: String, CaseIterable, Identifiable {
        case frame, image

        var id: Self { self }

        var title: String {
            switch self {
            case .frame: "Frame from Video"
            case .image: "Image"
            }
        }
    }

    @Environment(LibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    let target: Target
    @State private var mode: Mode = .frame
    @State private var time: Double = 0
    @State private var preview: Data?
    @State private var isLoadingFrame = false
    @State private var isSaving = false
    @State private var isImporting = false
    @State private var photo: PhotosPickerItem?
    @State private var problem: String?

    private var video: Video? {
        if case .video(let video) = target { return video }
        return nil
    }

    private var duration: Double {
        max(video?.duration ?? 0, 1)
    }

    private var hasCustomArtwork: Bool {
        switch target {
        case .video(let video): video.customArtworkKey != nil
        case .show(let show): show.customArtworkKey != nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if video != nil {
                    Picker("Source", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if mode == .frame, let video {
                    framePicker(video)
                } else {
                    imagePicker
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if hasCustomArtwork {
                    Button("Use Automatic Artwork", role: .destructive) {
                        switch target {
                        case .video(let video): library.resetArtwork(for: video)
                        case .show(let show): library.resetArtwork(for: show)
                        }
                        dismiss()
                    }
                }
            }
            .padding(Metrics.contentPadding)
            .navigationTitle("Choose Artwork")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if video == nil {
                    mode = .image
                } else if time == 0 {
                    time = min(duration * 0.1, 600)
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    problem = "That image couldn\u{2019}t be read."
                    return
                }
                Task { await save(imageData: data) }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await save(imageData: data)
                    } else {
                        problem = "That photo couldn\u{2019}t be read."
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
    }

    private func framePicker(_ video: Video) -> some View {
        VStack(spacing: 14) {
            ArtworkView(data: preview, shape: .still, maxPixelSize: 1_200, placeholderSymbol: "photo")
                .overlay {
                    if isLoadingFrame, preview == nil {
                        ProgressView()
                    }
                }
                .frame(maxWidth: 640)
                .artworkShadow(isProminent: false)
            Slider(value: $time, in: 0...duration) {
                Text("Position")
            }
            .frame(maxWidth: 640)
            Text(PlaybackLabel.time(time, of: duration))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                Task {
                    isSaving = true
                    defer { isSaving = false }
                    if await library.setArtworkFromFrame(of: video, at: time) {
                        dismiss()
                    } else {
                        problem = "Coreplay couldn\u{2019}t take a frame from this video."
                    }
                }
            } label: {
                Label("Use This Frame", systemImage: "checkmark")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || !video.isAvailable)
        }
        // Grab a new preview when the slider settles on a different half-second.
        .task(id: Int(time * 2)) {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            isLoadingFrame = true
            let frame = await library.frame(of: video, at: time, maxPixelSize: 960)
            guard !Task.isCancelled else { return }
            isLoadingFrame = false
            if let frame {
                preview = frame
            }
        }
    }

    private var imagePicker: some View {
        VStack(spacing: 14) {
            currentArtwork
                .frame(maxWidth: 260, maxHeight: 360)
                .artworkShadow(isProminent: false)
            HStack(spacing: 12) {
                Button {
                    isImporting = true
                } label: {
                    Label("Choose File\u{2026}", systemImage: "folder")
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose from Photos\u{2026}", systemImage: "photo.on.rectangle")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isSaving)
            Text("Posters look best at 2:3, like a film poster.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var currentArtwork: some View {
        switch target {
        case .video(let video):
            ArtworkView(url: library.artworkURL(video.posterArtworkKey ?? video.stillArtworkKey, .large), shape: video.posterArtworkKey == nil ? .still : .poster, maxPixelSize: 700, placeholderSymbol: "film")
        case .show(let show):
            ArtworkView(url: library.artworkURL(show.posterArtworkKey, .large), shape: .poster, maxPixelSize: 700, placeholderSymbol: "tv")
        }
    }

    private func save(imageData: Data) async {
        isSaving = true
        defer { isSaving = false }
        let saved: Bool
        switch target {
        case .video(let video): saved = await library.setArtwork(imageData: imageData, for: video)
        case .show(let show): saved = await library.setArtwork(imageData: imageData, for: show)
        }
        if saved {
            dismiss()
        } else {
            problem = "That image couldn\u{2019}t be used."
        }
    }
}

enum PlaybackLabel {
    /// "12:04 of 1:58:22".
    static func time(_ seconds: Double, of duration: Double) -> String {
        let position = PlaybackTimeFormatter.string(from: seconds, referenceDuration: duration)
        let total = PlaybackTimeFormatter.string(from: duration, referenceDuration: duration)
        return "\(position) of \(total)"
    }
}
