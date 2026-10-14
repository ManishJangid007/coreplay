import DesignSystem
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// The song's words in Now Playing, in place of the artwork. Synced lyrics
/// follow the song, the line being sung bright, and a tap on a line jumps
/// there; plain lyrics scroll.
struct LyricsView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lyrics: Lyrics?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let lyrics {
                if lyrics.isSynced {
                    synced(lyrics)
                } else {
                    ScrollView {
                        Text(lyrics.lines.map(\.text).joined(separator: "\n"))
                            .font(.title3.weight(.semibold))
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 40, weight: .light))
                    Text("No Lyrics")
                        .font(.title3.weight(.semibold))
                    Text("Put an .lrc file with the song\u{2019}s name beside it, or turn on Look Up Lyrics in Settings.")
                        .font(.callout)
                        .foregroundStyle(Palette.secondaryOnDark)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: session.currentItem?.id) {
            isLoading = true
            lyrics = nil
            if let item = session.currentItem {
                lyrics = await session.lyricsLookup?(item)
            }
            isLoading = false
        }
    }

    private func synced(_ lyrics: Lyrics) -> some View {
        let current = lyrics.lineIndex(at: session.controller.currentTime)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                        Text(line.text.isEmpty ? "\u{266A}" : line.text)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(index == current ? Palette.primaryOnDark : Palette.secondaryOnDark.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let time = line.time {
                                    Task { await session.seek(to: time) }
                                }
                            }
                            .id(index)
                            .accessibilityAddTraits(index == current ? .isSelected : [])
                    }
                }
                .padding(.vertical, 120)
            }
            .scrollIndicators(.hidden)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.15), .init(color: .black, location: 0.85), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .onChange(of: current, initial: true) { _, line in
                guard let line else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                    proxy.scrollTo(line, anchor: .center)
                }
            }
        }
    }
}

/// Sleep timer: stop after a while, or at the end of what's playing.
struct SleepTimerMenu: View {
    @Environment(PlaybackSession.self) private var session

    var body: some View {
        Menu {
            Section("Stop Playing") {
                ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button("In \(minutes) Minutes") {
                        session.setSleepTimer(.minutes(minutes))
                    }
                }
                Button(session.controller.hasVideo ? "When This Video Ends" : "When This Song Ends") {
                    session.setSleepTimer(.endOfItem)
                }
            }
            if session.sleepTimer != nil {
                Button("Turn Off Sleep Timer", systemImage: "xmark", role: .destructive) {
                    session.setSleepTimer(nil)
                }
            }
        } label: {
            Image(systemName: session.sleepTimer == nil ? "moon.zzz" : "moon.zzz.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(session.sleepTimer == nil ? Palette.primaryOnDark : Color.accentColor)
                .frame(width: Metrics.playerButtonSize, height: Metrics.playerButtonSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(label))
        #if os(macOS)
        .help(label)
        #endif
    }

    private var label: String {
        switch session.sleepTimer {
        case nil: return "Sleep Timer"
        case .endOfItem: return "Sleep Timer: when this ends"
        case .minutes:
            guard let deadline = session.sleepDeadline else { return "Sleep Timer" }
            return "Sleep Timer: stops at \(deadline.formatted(date: .omitted, time: .shortened))"
        }
    }
}
