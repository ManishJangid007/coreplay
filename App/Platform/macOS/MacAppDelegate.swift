#if os(macOS)
import AppKit
import SwiftUI

/// Receives files opened from Finder (double-click, Open With) or dropped on
/// the Dock icon. Implementing `application(_:open:)` keeps SwiftUI from
/// spawning a new window per file.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var pendingURLs: [URL] = []
    private var openMainWindow: (() -> Void)?

    /// Connects the delegate to the app model and to SwiftUI's way of opening
    /// the main window; files that arrived during launch are played now.
    func attach(to model: AppModel, openMainWindow: @escaping () -> Void) {
        self.model = model
        self.openMainWindow = openMainWindow
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

    /// Clicking the Dock icon brings the main window back. SwiftUI does that
    /// only when no window is visible, and the invisible window a video waits
    /// in while no player shows it (`VideoParking`) counts as one.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard flag, let openMainWindow,
              !sender.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return true }
        openMainWindow()
        return false
    }

    // MARK: Dock menu

    /// Right-click the Dock icon: what's playing, play/pause, next and previous.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let model, model.session.hasItem else { return nil }
        let controller = model.session.controller
        let menu = NSMenu()
        let title = NSMenuItem(title: controller.displayTitle, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if let subtitle = controller.displaySubtitle, !subtitle.isEmpty {
            let detail = NSMenuItem(title: subtitle, action: nil, keyEquivalent: "")
            detail.isEnabled = false
            menu.addItem(detail)
        }
        menu.addItem(.separator())
        menu.addItem(item(controller.isPlaying ? "Pause" : "Play", action: #selector(togglePlayPause)))
        let next = item("Next", action: #selector(playNext))
        next.isEnabled = model.session.queue.hasNext
        menu.addItem(next)
        menu.addItem(item("Previous", action: #selector(playPrevious)))
        if controller.hasVideo {
            menu.addItem(.separator())
            menu.addItem(item("Show Video", action: #selector(showPlayer)))
        }
        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func togglePlayPause() {
        model?.session.togglePlayPause()
    }

    @objc private func playNext() {
        guard let session = model?.session else { return }
        Task { await session.next() }
    }

    @objc private func playPrevious() {
        guard let session = model?.session else { return }
        Task { await session.previous() }
    }

    @objc private func showPlayer() {
        NSApp.activate()
        model?.presentPlayer()
    }
}

/// Attaches the app delegate from inside the main window, where SwiftUI's
/// `openWindow` action is available.
struct MacAppDelegateAttachment: ViewModifier {
    let appDelegate: MacAppDelegate
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            appDelegate.attach(to: model) { openWindow(id: "main") }
        }
    }
}
#endif
