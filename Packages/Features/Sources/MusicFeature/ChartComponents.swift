import DesignSystem
import MediaLibrary
import SwiftUI

// Music lists in the style of Apple Music's and Spotify's charts: numbered
// rows with artwork and bold titles that light up under the pointer, genre
// tiles in colour, and artists as portraits.

/// A song as a chart row: its number (a play button under the pointer, a
/// waveform while it plays), artwork, the title over the artist, the album
/// in its own column when there's room, and the length. Rows alternate with
/// a faint stripe.
struct ChartTrackRow: View {
    @Environment(LibraryManager.self) private var library
    let track: Track
    /// Track number or chart position; `nil` hides the column.
    var number: Int?
    var showsArtwork = true
    var showsArtist = true
    /// The album in a column of its own, for wide lists.
    var showsAlbum = false
    var isCurrent = false
    var isStriped = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            if let number {
                numberColumn(number)
            }
            if showsArtwork {
                ArtworkView(
                    url: library.artworkURL(track.artworkKey ?? track.album?.artworkKey, .thumbnail),
                    shape: .square,
                    maxPixelSize: 150,
                    placeholderSymbol: "music.note"
                )
                .frame(width: 46, height: 46)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                    if track.file?.isLossless == true {
                        // Beside the title, as Music marks Lossless and
                        // Explicit, so the columns stay lined up.
                        Text("LOSSLESS")
                            .font(.system(size: 8.5, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .overlay(RoundedRectangle(cornerRadius: 3.5, style: .continuous).stroke(.secondary.opacity(0.6), lineWidth: 1))
                            .fixedSize()
                            .accessibilityLabel(Text("Lossless"))
                    }
                }
                if showsArtist {
                    Text(showsAlbum ? track.artistName : "\(track.artistName) \u{00B7} \(track.albumTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsAlbum {
                Text(track.albumTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(MusicFormat.duration(track.duration))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, showsArtwork ? 7 : 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .opacity(track.isAvailable ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isCurrent ? "Now playing" : (track.isAvailable ? "" : "Not available")))
    }

    private var rowFill: Color {
        if isHovering { return Color.primary.opacity(0.09) }
        if isCurrent { return Color.accentColor.opacity(0.12) }
        return isStriped ? Color.primary.opacity(0.035) : .clear
    }

    private func numberColumn(_ number: Int) -> some View {
        ZStack {
            if isCurrent {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative)
                    .foregroundStyle(Color.accentColor)
            } else if isHovering {
                Image(systemName: "play.fill")
                    .foregroundStyle(.primary)
            } else {
                Text("\(number)")
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34)
        .accessibilityHidden(true)
    }
}

/// "Top Songs": the songs you play most, numbered like a chart.
struct TopSongsChart: View {
    let tracks: [Track]
    let isCurrent: (Track) -> Bool
    let onPlay: (Track) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Top Songs")
                    .font(.title2.bold())
                Text("Your most played")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 18, alignment: .top)], alignment: .leading, spacing: 2) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        onPlay(track)
                    } label: {
                        ChartTrackRow(track: track, number: index + 1, isCurrent: isCurrent(track))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Column titles over a wide song list.
struct ChartColumnHeader: View {
    var showsNumber = false
    var showsArtwork = true
    var showsAlbum = true

    var body: some View {
        HStack(spacing: 14) {
            if showsNumber {
                Text("#").frame(width: 34)
            }
            if showsArtwork {
                Color.clear.frame(width: 46, height: 1)
            }
            Text("Title").frame(maxWidth: .infinity, alignment: .leading)
            if showsAlbum {
                Text("Album").frame(maxWidth: .infinity, alignment: .leading)
            }
            Image(systemName: "clock")
                .frame(minWidth: 44, alignment: .trailing)
                .accessibilityLabel(Text("Length"))
        }
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
        }
    }
}

/// A genre as a coloured tile with a couple of its covers tipped into the
/// corner, as in Music's and Spotify's browse pages.
struct GenreTile: View {
    @Environment(LibraryManager.self) private var library
    let genre: Genre
    @State private var isHovering = false

    var body: some View {
        let colors = Self.colors(for: genre.name)
        let covers = Array(genre.albums.compactMap(\.artworkKey).prefix(2))
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack {
                ForEach(Array(covers.enumerated().reversed()), id: \.offset) { index, key in
                    ArtworkView(url: library.artworkURL(key, .grid), shape: .square, maxPixelSize: 300, placeholderSymbol: "music.note")
                        .frame(width: 84, height: 84)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                        .rotationEffect(.degrees(index == 0 ? 22 : 8))
                        .offset(x: index == 0 ? 14 : -40, y: index == 0 ? 8 : 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 10)
            .padding(.bottom, -6)
            .scaleEffect(isHovering ? 1.05 : 1, anchor: .bottomTrailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(genre.name)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                Text(Self.songCount(genre.tracks.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(14)
        }
        .aspectRatio(1.7, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(isHovering ? 0.3 : 0.15), radius: isHovering ? 12 : 6, y: 4)
        .onHover { isHovering = $0 }
        .animation(Motion.quick, value: isHovering)
        .accessibilityElement(children: .combine)
    }

    static func songCount(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count) songs"
    }

    /// The same colours for a genre every time.
    static func colors(for name: String) -> (Color, Color) {
        let palette: [(Color, Color)] = [
            (Color(red: 0.91, green: 0.17, blue: 0.47), Color(red: 0.48, green: 0.15, blue: 0.67)),
            (Color(red: 0.98, green: 0.45, blue: 0.13), Color(red: 0.86, green: 0.15, blue: 0.20)),
            (Color(red: 0.07, green: 0.62, blue: 0.68), Color(red: 0.13, green: 0.30, blue: 0.72)),
            (Color(red: 0.20, green: 0.70, blue: 0.38), Color(red: 0.05, green: 0.45, blue: 0.47)),
            (Color(red: 0.36, green: 0.30, blue: 0.86), Color(red: 0.62, green: 0.20, blue: 0.75)),
            (Color(red: 0.96, green: 0.67, blue: 0.11), Color(red: 0.90, green: 0.36, blue: 0.10)),
            (Color(red: 0.84, green: 0.13, blue: 0.27), Color(red: 0.95, green: 0.42, blue: 0.53)),
            (Color(red: 0.10, green: 0.55, blue: 0.90), Color(red: 0.30, green: 0.20, blue: 0.78)),
            (Color(red: 0.55, green: 0.76, blue: 0.20), Color(red: 0.13, green: 0.55, blue: 0.30)),
            (Color(red: 0.80, green: 0.25, blue: 0.75), Color(red: 0.98, green: 0.50, blue: 0.30)),
        ]
        var hash = 5_381
        for scalar in name.lowercased().unicodeScalars {
            hash = (hash &* 33 &+ Int(scalar.value)) & 0x7FFF_FFFF
        }
        return palette[hash % palette.count]
    }
}

/// An artist as a round portrait with their name and what's in the library.
struct ArtistTile: View {
    @Environment(LibraryManager.self) private var library
    let artist: Artist
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 10) {
            ArtistPortrait(artworkURL: library.artworkURL(artist.artworkKey, .grid), size: 150)
                .shadow(color: .black.opacity(isHovering ? 0.35 : 0.2), radius: isHovering ? 14 : 8, y: 4)
                .scaleEffect(isHovering ? 1.04 : 1)
            VStack(spacing: 2) {
                Text(artist.name)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(Motion.quick, value: isHovering)
        .accessibilityElement(children: .combine)
    }

    /// "2 albums · 18 songs".
    private var summary: String {
        let albums = artist.albums.count
        let songs = artist.tracks.count
        var parts: [String] = []
        if albums > 0 { parts.append(albums == 1 ? "1 album" : "\(albums) albums") }
        parts.append(GenreTile.songCount(songs))
        return parts.joined(separator: " \u{00B7} ")
    }
}
