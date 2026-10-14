import AppIntents
import SwiftUI
import WidgetKit

/// Coreplay's widgets: playback controls for the Home Screen, Lock Screen
/// neighbours and the Mac's desktop and Notification Center.
@main
struct CoreplayWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaybackControlsWidget()
    }
}

struct ControlsEntry: TimelineEntry {
    let date: Date
}

struct ControlsProvider: TimelineProvider {
    func placeholder(in context: Context) -> ControlsEntry {
        ControlsEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (ControlsEntry) -> Void) {
        completion(ControlsEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ControlsEntry>) -> Void) {
        completion(Timeline(entries: [ControlsEntry(date: .now)], policy: .never))
    }
}

struct PlaybackControlsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PlaybackControls", provider: ControlsProvider()) { _ in
            ControlsView()
        }
        .configurationDisplayName("Coreplay Controls")
        .description("Play, pause and skip, or shuffle all your music.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ControlsView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                Text("Coreplay")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            HStack(spacing: family == .systemSmall ? 8 : 14) {
                control(PreviousItemIntent(), symbol: "backward.fill", label: "Previous")
                control(PlayPauseIntent(), symbol: "playpause.fill", label: "Play or Pause")
                control(NextItemIntent(), symbol: "forward.fill", label: "Next")
                if family == .systemMedium {
                    Spacer(minLength: 0)
                    Button(intent: ShuffleMusicIntent()) {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.22), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.26, blue: 0.42), Color(red: 0.56, green: 0.18, blue: 0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func control(_ intent: some AppIntent, symbol: String, label: String) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.22), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(Text(label))
    }
}

// The app's playback intents, by the same names: they're audio playback
// intents, so the system performs them in the app (App/Coreplay/AppIntents.swift),
// which plays through its own session. These copies only name them here.

struct PlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct NextItemIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next"

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct PreviousItemIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous"

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct ShuffleMusicIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Shuffle My Music"

    func perform() async throws -> some IntentResult {
        .result()
    }
}
