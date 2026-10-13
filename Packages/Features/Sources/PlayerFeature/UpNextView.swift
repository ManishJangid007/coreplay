import DesignSystem
import NowPlaying
import PlaybackCore
import SwiftUI

/// The queue: what's playing, Up Next (reorder, swipe to remove, tap to
/// play) and history, with shuffle and repeat like Apple Music.
public struct UpNextView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if let current = session.currentItem {
                    Section("Now Playing") {
                        QueueRow(item: current, isCurrent: true)
                    }
                }

                Section {
                    if session.upNext.isEmpty {
                        Text("Nothing up next")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.upNext) { item in
                        Button {
                            Task { await session.jump(to: item) }
                        } label: {
                            QueueRow(item: item, isCurrent: false)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let upcoming = session.upNext
                        let removed = offsets.compactMap { upcoming.indices.contains($0) ? upcoming[$0] : nil }
                        for item in removed {
                            session.removeFromQueue(item)
                        }
                    }
                    .onMove { source, destination in
                        session.moveUpNext(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    HStack {
                        Text("Up Next")
                        Spacer()
                        Button {
                            session.toggleShuffle()
                        } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(session.isShuffled ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(session.isShuffled ? "Shuffle On" : "Shuffle Off"))
                        Button {
                            session.cycleRepeatMode()
                        } label: {
                            Image(systemName: session.repeatMode == .one ? "repeat.1" : "repeat")
                                .foregroundStyle(session.repeatMode == .off ? Color.secondary : Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Repeat"))
                    }
                }

                if !session.queue.history.isEmpty {
                    Section("History") {
                        ForEach(Array(session.queue.history.reversed().enumerated()), id: \.offset) { _, item in
                            QueueRow(item: item, isCurrent: false)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Queue")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 460)
        #endif
    }
}

private struct QueueRow: View {
    let item: PlaybackItem
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .video ? "play.rectangle.fill" : "music.note")
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                if let artist = item.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(Text("Now playing"))
            }
        }
        .contentShape(Rectangle())
    }
}
