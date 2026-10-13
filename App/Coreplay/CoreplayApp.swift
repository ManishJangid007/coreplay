import MediaLibrary
import NowPlaying
import PlayerFeature
import SettingsFeature
import SwiftData
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
        .environment(model.library)
        .modelContainer(model.library.container)
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
        .environment(model.library)
        .modelContainer(model.library.container)
        .defaultSize(width: 1_120, height: 740)
        .commands {
            CoreplayCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model.settings)
                .environment(model.session)
                .environment(model.library)
        }
        #endif
    }
}
