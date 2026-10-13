import DesignSystem
import MediaLibrary
import NowPlaying
import SwiftData
import SwiftUI

/// Every song, alphabetically, with Play and Shuffle at the top.
public struct SongsView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Query(sort: \Track.sortTitle) private var tracks: [Track]
    @State private var editingTrack: Track?

    public init() {}

    public var body: some View {
        let playback = MusicPlayback(library: library, session: session)
        Group {
            if tracks.isEmpty {
                MusicEmptyState()
            } else {
                List {
                    PlayShuffleButtons(
                        onPlay: { playback.play(tracks, shuffled: false) },
                        onShuffle: { playback.shuffle(tracks) }
                    )
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    ForEach(tracks) { track in
                        Button {
                            playback.play(tracks, startingAt: track)
                        } label: {
                            TrackRow(track: track, isCurrent: playback.isCurrent(track))
                        }
                        .buttonStyle(.plain)
                        .disabled(!track.isAvailable)
                        .contextMenu {
                            TrackMenuItems(tracks: [track], onEditInfo: { editingTrack = track })
                        }
                        #if os(iOS)
                        .swipeActions(edge: .leading) {
                            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                                playback.playNext([track])
                            }
                            .tint(.indigo)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") {
                                playback.playLater([track])
                            }
                            .tint(.orange)
                        }
                        #endif
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Songs")
        .sheet(item: $editingTrack) { track in
            TrackEditView(track: track)
        }
    }
}

/// A song with its artwork, artist and album, as in Music's song lists.
public struct TrackRow: View {
    @Environment(LibraryManager.self) private var library
    private let track: Track
    private let isCurrent: Bool

    public init(track: Track, isCurrent: Bool = false) {
        self.track = track
        self.isCurrent = isCurrent
    }

    public var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                url: library.artworkURL(track.artworkKey ?? track.album?.artworkKey, .thumbnail),
                shape: .square,
                maxPixelSize: 140,
                placeholderSymbol: "music.note"
            )
            .frame(width: 44, height: 44)
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: ArtworkShape.square.cornerRadius, style: .continuous)
                        .fill(.black.opacity(0.4))
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(MusicFormat.duration(track.duration))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .opacity(track.isAvailable ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isCurrent ? "Now playing" : (track.isAvailable ? "" : "Not available")))
    }

    private var subtitle: String {
        "\(track.artistName) \u{2014} \(track.albumTitle)"
    }
}

/// Edit Info: corrections stay put when the folder is scanned again.
struct TrackEditView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var edit: TrackEdit
    @State private var yearText: String
    @State private var trackText: String
    @State private var discText: String
    @State private var genreText: String

    init(track: Track) {
        self.track = track
        let edit = TrackEdit(track: track)
        _edit = State(initialValue: edit)
        _yearText = State(initialValue: edit.year.map(String.init) ?? "")
        _trackText = State(initialValue: edit.trackNumber.map(String.init) ?? "")
        _discText = State(initialValue: edit.discNumber.map(String.init) ?? "")
        _genreText = State(initialValue: edit.genre ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $edit.title)
                    TextField("Artist", text: $edit.artist)
                    TextField("Album", text: $edit.album)
                    TextField("Album Artist", text: $edit.albumArtist)
                    TextField("Genre", text: $genreText)
                }
                Section {
                    TextField("Year", text: $yearText)
                    TextField("Track Number", text: $trackText)
                    TextField("Disc Number", text: $discText)
                    Toggle("Part of a Compilation", isOn: $edit.isCompilation)
                }
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                if let file = track.file {
                    Section("File") {
                        LabeledContent("Name", value: file.fileName)
                        if let codec = file.codec {
                            LabeledContent("Format", value: formatDescription(codec: codec, file: file))
                        }
                    }
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
                    Button("Done") {
                        save()
                        dismiss()
                    }
                    .disabled(edit.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
    }

    private func save() {
        var final = edit
        final.title = final.title.trimmingCharacters(in: .whitespaces)
        final.artist = nonEmpty(final.artist) ?? "Unknown Artist"
        final.album = nonEmpty(final.album) ?? "Unknown Album"
        final.albumArtist = nonEmpty(final.albumArtist) ?? final.artist
        final.genre = nonEmpty(genreText)
        final.year = Int(yearText.trimmingCharacters(in: .whitespaces))
        final.trackNumber = Int(trackText.trimmingCharacters(in: .whitespaces))
        final.discNumber = Int(discText.trimmingCharacters(in: .whitespaces))
        library.apply(final, to: track)
    }

    private func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formatDescription(codec: String, file: MediaFile) -> String {
        var parts = [codec]
        if let bits = file.bitsPerSample, let rate = file.sampleRate {
            let kilohertz = (Double(rate) / 1000).formatted(.number.precision(.fractionLength(0...1)))
            parts.append("\(bits)-bit/\(kilohertz) kHz")
        } else if let bitRate = file.bitRate {
            parts.append("\(bitRate / 1000) kbps")
        }
        return parts.joined(separator: ", ")
    }
}
