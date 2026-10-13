import SwiftUI

/// App-level actions feature modules can trigger without knowing about each
/// other or about the app target (opening files, showing settings…).
public struct AppActions: Sendable {
    public var openFiles: @MainActor @Sendable () -> Void
    public var openSettings: @MainActor @Sendable () -> Void
    public var showPlayer: @MainActor @Sendable () -> Void
    /// Asks for a folder to add to the library (Files picker or open panel).
    public var addLibraryFolder: @MainActor @Sendable () -> Void

    public init(
        openFiles: @escaping @MainActor @Sendable () -> Void,
        openSettings: @escaping @MainActor @Sendable () -> Void,
        showPlayer: @escaping @MainActor @Sendable () -> Void,
        addLibraryFolder: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.openFiles = openFiles
        self.openSettings = openSettings
        self.showPlayer = showPlayer
        self.addLibraryFolder = addLibraryFolder
    }

    /// Does nothing; used for previews and as the environment default.
    public static let inert = AppActions(openFiles: {}, openSettings: {}, showPlayer: {})
}

public extension EnvironmentValues {
    @Entry var appActions: AppActions = .inert
}
