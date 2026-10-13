import DesignSystem
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// Home: Apple TV's "Watch Now" plus Apple Music's "Listen Now".
///
/// Until the library exists (Milestones 3–4) it shows what's playing and an
/// invitation to open files. Continue Watching, Up Next, Recently Added and
/// the generated rows plug in here once there's data.
public struct HomeView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let item = session.currentItem {
                    NowPlayingCard(item: item, controller: session.controller) {
                        actions.showPlayer()
                    }
                }
                welcome
            }
            .padding(Metrics.contentPadding)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    actions.openFiles()
                } label: {
                    Label("Open Files", systemImage: "plus")
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    actions.openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            #endif
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                BrandLogo(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Brand.appName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("Play Anything")
                        .font(.title2.bold())
                }
            }
            Text("Open movies, shows, music or home videos in any format VLC supports, including MKV, AVI, FLAC and Opus, with every subtitle and audio track.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button {
                    actions.openFiles()
                } label: {
                    Label("Open Files\u{2026}", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                #if os(macOS)
                Text("or drop files onto this window")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                #endif
            }
            Text("Your library, with artwork and Continue Watching, arrives once folders can be added in Sources.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A large card for whatever is currently loaded, with its progress.
private struct NowPlayingCard: View {
    let item: PlaybackItem
    let controller: PlaybackController
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 16) {
                ArtworkView(
                    data: controller.metadata.artworkData,
                    shape: controller.hasVideo ? .still : .square,
                    maxPixelSize: 400
                )
                .frame(width: controller.hasVideo ? 160 : 90)
                .artworkShadow(isProminent: false)

                VStack(alignment: .leading, spacing: 6) {
                    Text(controller.isPlaying ? "Now Playing" : "Paused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(controller.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                    if let duration = controller.duration, duration > 0 {
                        ProgressView(value: min(controller.currentTime / duration, 1))
                            .tint(.primary)
                        Text(PlaybackTimeFormatter.string(from: max(0, duration - controller.currentTime), referenceDuration: duration) + " left")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the player"))
    }
}
