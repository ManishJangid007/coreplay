#if os(macOS)
import NowPlaying
import PlaybackEngine
import SwiftUI

/// File and Playback menus. Shortcuts follow VLC and QuickTime: ⌘O open,
/// ⌘←/⌘→ previous/next, ⌥⌘←/⌥⌘→ skip 10 s, ⌘↑/⌘↓ volume. Space and the
/// plain arrow keys are handled by the player views so they never steal
/// typing from text fields.
struct CoreplayCommands: Commands {
    let model: AppModel

    private var session: PlaybackSession { model.session }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open\u{2026}") {
                model.presentOpenPanel()
            }
            .keyboardShortcut("o")

            Button("Add Folder to Library\u{2026}") {
                model.presentFolderPanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Check for New Files") {
                model.library.scanAll()
            }
            .disabled(model.library.isScanning)
        }

        CommandMenu("Playback") {
            Button(session.controller.isPlaying ? "Pause" : "Play") {
                session.togglePlayPause()
            }
            .disabled(!session.hasItem)

            Button(model.isPlayerPresented ? "Hide Player" : "Show Player") {
                if model.isPlayerPresented {
                    model.dismissPlayer()
                } else {
                    model.presentPlayer()
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(!session.hasItem)

            Button("Stop") {
                Task { await session.stop() }
            }
            .keyboardShortcut(".")
            .disabled(!session.hasItem)

            Divider()

            Button("Next") {
                Task { await session.next() }
            }
            .keyboardShortcut(.rightArrow)
            .disabled(!session.queue.hasNext)

            Button("Previous") {
                Task { await session.previous() }
            }
            .keyboardShortcut(.leftArrow)
            .disabled(!session.hasItem)

            Divider()

            Button("Skip Forward 10 Seconds") {
                Task { await session.skip(by: 10) }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(!session.hasItem)

            Button("Skip Back 10 Seconds") {
                Task { await session.skip(by: -10) }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(!session.hasItem)

            Divider()

            Button("Volume Up") {
                session.controller.setVolume(session.controller.volume + 0.1)
            }
            .keyboardShortcut(.upArrow)

            Button("Volume Down") {
                session.controller.setVolume(session.controller.volume - 0.1)
            }
            .keyboardShortcut(.downArrow)

            Button(session.controller.isMuted ? "Unmute" : "Mute") {
                session.controller.setMuted(!session.controller.isMuted)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Divider()

            Toggle("Shuffle", isOn: Binding(
                get: { session.isShuffled },
                set: { _ in session.toggleShuffle() }
            ))

            Picker("Repeat", selection: Binding(
                get: { session.repeatMode },
                set: { session.repeatMode = $0 }
            )) {
                Text("Off").tag(PlaybackQueue.RepeatMode.off)
                Text("All").tag(PlaybackQueue.RepeatMode.all)
                Text("One").tag(PlaybackQueue.RepeatMode.one)
            }
        }
    }
}
#endif
