import DesignSystem
import PlaybackCore
import SwiftUI

/// The card the player shows when the end credits roll and another episode
/// is queued, as the TV app does: the next episode's still with a countdown
/// ring, its title, Play Now, and a way to keep watching the credits.
struct UpNextCard: View {
    let item: PlaybackItem
    /// `nil` when the next episode waits for the viewer (autoplay is off).
    let countdown: UpNextPolicy.Countdown?
    let onPlay: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onPlay) {
                ArtworkView(url: item.artworkURL, shape: .still, maxPixelSize: 400, placeholderSymbol: "tv")
                    .frame(width: 136)
                    .overlay {
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.45))
                                .frame(width: 46, height: 46)
                            if let countdown {
                                Circle()
                                    .stroke(.white.opacity(0.25), lineWidth: 3)
                                    .frame(width: 40, height: 40)
                                Circle()
                                    .trim(from: 0, to: countdown.fraction)
                                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 40, height: 40)
                                    .animation(.linear(duration: 0.25), value: countdown.fraction)
                            }
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Play \(item.title)"))

            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.secondaryOnDark)
                    .monospacedDigit()
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                if let detail = item.artist, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryOnDark)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Button(action: onPlay) {
                        Label("Play Now", systemImage: "play.fill")
                    }
                    .buttonStyle(HeroPlayButtonStyle())
                    .controlSize(.small)
                    Button(action: onDismiss) {
                        Text(countdown == nil ? "Not Now" : "Watch Credits")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 46)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background(.white.opacity(0.16), in: Capsule())
                }
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
        }
        .padding(12)
        .frame(maxWidth: 460, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Up Next"))
    }

    private var heading: String {
        guard let countdown else { return "Up Next" }
        let seconds = Int(countdown.remaining.rounded(.up))
        return seconds > 0 ? "Next Episode in \(seconds)" : "Starting\u{2026}"
    }
}
