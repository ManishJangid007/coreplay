import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI

/// Every video in the library, by name. Movies and TV shows get their own
/// sections, with posters and episodes, in Milestone 4; until then they're here.
public struct VideosView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    @Query(filter: #Predicate<MediaFile> { $0.kindRaw == "video" }, sort: \MediaFile.fileName)
    private var videos: [MediaFile]

    public init() {}

    public var body: some View {
        Group {
            if videos.isEmpty {
                EmptyStateView(
                    "No Videos Yet",
                    systemImage: "video",
                    message: "Videos in the folders you add to Sources appear here.",
                    actionTitle: "Add Folder\u{2026}",
                    action: { actions.addLibraryFolder() }
                )
            } else {
                List(videos) { file in
                    Button {
                        play(file)
                    } label: {
                        VideoRow(file: file)
                    }
                    .buttonStyle(.plain)
                    .disabled(!file.isAvailable)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Home Videos")
    }

    private func play(_ file: MediaFile) {
        guard let item = library.playbackItem(for: file) else { return }
        Task {
            await session.play(item)
        }
        actions.showPlayer()
    }
}

private struct VideoRow: View {
    let file: MediaFile

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: ArtworkShape.still.cornerRadius, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(width: 96)
                .overlay {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(PlaybackItem.displayTitle(for: URL(filePath: file.fileName)))
                    .lineLimit(2)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .opacity(file.isAvailable ? 1 : 0.45)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if let duration = file.duration, duration > 0 {
            parts.append(PlaybackTimeFormatter.string(from: duration, referenceDuration: duration))
        }
        parts.append(file.fileExtension.uppercased())
        if !file.isAvailable {
            parts.append("Not available")
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
