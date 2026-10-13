#if os(macOS)
import AppKit

/// Receives files opened from Finder (double-click, Open With) or dropped on
/// the Dock icon. Implementing `application(_:open:)` keeps SwiftUI from
/// spawning a new window per file.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var pendingURLs: [URL] = []

    /// Connects the delegate to the app model; files that arrived during
    /// launch are played now.
    func attach(to model: AppModel) {
        self.model = model
        if !pendingURLs.isEmpty {
            model.open(pendingURLs, securityScoped: false)
            pendingURLs.removeAll()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let model {
            model.open(urls, securityScoped: false)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    /// Music keeps playing after the last window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
#endif
