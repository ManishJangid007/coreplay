import NowPlaying
import PlayerFeature
import SettingsFeature
import SwiftUI

@main
struct CoreplayApp: App {
    @State private var model = AppModel()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            PhoneRootView()
        }
        .environment(model)
        .environment(model.session)
        .environment(model.settings)
        #else
        // A single main window, like Music: it appears in the Window menu and
        // reopens from the Dock after being closed.
        Window("Coreplay", id: "main") {
            MacRootView()
                .task { appDelegate.attach(to: model) }
        }
        .environment(model)
        .environment(model.session)
        .environment(model.settings)
        .defaultSize(width: 1_120, height: 740)
        .commands {
            CoreplayCommands(model: model)
        }

        Window("Video", id: VideoWindow.id) {
            VideoWindow()
                .environment(model)
                .environment(model.session)
                .environment(model.settings)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 540)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(model.settings)
                .environment(model.session)
        }
        #endif
    }
}
