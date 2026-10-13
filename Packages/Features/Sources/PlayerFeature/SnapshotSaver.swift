import Foundation
import PlaybackCore
import PlaybackEngine

#if os(iOS)
import Photos
#endif

/// Saves the frame on screen: to Pictures ▸ Coreplay on the Mac, and to the
/// photo library on iPhone and iPad.
@MainActor
public enum SnapshotSaver {
    /// Returns where the picture went, for the confirmation ("Pictures", "Photos").
    public static func save(_ controller: PlaybackController) async throws -> String {
        let name = fileName(for: controller)
        #if os(macOS)
        guard let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else {
            throw PlaybackError(.accessDenied, "Coreplay can\u{2019}t find your Pictures folder.")
        }
        let folder = pictures.appending(path: "Coreplay", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await controller.saveSnapshot(to: uniqueURL(in: folder, name: name))
        return "Pictures"
        #else
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).png")
        try await controller.saveSnapshot(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PlaybackError(.accessDenied, "To save pictures, allow Coreplay to add to your photo library in Settings.")
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: url, options: nil)
        }
        return "Photos"
        #endif
    }

    /// "Heat 1-02-03": the title and position, safe for any file system.
    static func fileName(for controller: PlaybackController) -> String {
        let title = controller.displayTitle.isEmpty ? "Coreplay" : controller.displayTitle
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: " ")
        let position = PlaybackTimeFormatter.string(from: controller.currentTime, referenceDuration: controller.duration)
            .replacingOccurrences(of: ":", with: "-")
        return "\(cleaned.prefix(80)) \(position)"
    }

    private static func uniqueURL(in folder: URL, name: String) -> URL {
        var url = folder.appending(path: "\(name).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(name) \(counter).png")
            counter += 1
        }
        return url
    }
}
