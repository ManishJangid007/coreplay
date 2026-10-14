import Foundation
import Observation
import PlaybackCore
internal import VLCKit

/// Chromecasts and TVs VLC can send to, found with its renderer discovery
/// (Bonjour for Chromecasts, UPnP for TVs that speak DLNA). Choosing one
/// moves playback there: the player switches to VLC, which streams the item
/// to the device.
@MainActor
@Observable
public final class CastingCenter {
    public static let shared = CastingCenter()

    public struct Target: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        /// VLC's renderer type, such as "chromecast" or "dlna".
        public let kind: String
        public let playsVideo: Bool
        public let playsAudio: Bool

        public var systemImage: String {
            playsVideo ? "tv" : "hifispeaker"
        }
    }

    /// Devices found so far, by name.
    public private(set) var targets: [Target] = []
    /// Where playback goes, or `nil` for this device.
    public private(set) var activeTarget: Target?
    public private(set) var isSearching = false

    public var isCasting: Bool { activeTarget != nil }

    /// Called when the target changes, so the player can move playback.
    @ObservationIgnored public var onTargetChange: (@MainActor (Target?) -> Void)?

    @ObservationIgnored private var discoverers: [(VLCRendererDiscoverer, RendererBridge)] = []
    @ObservationIgnored private var items: [String: VLCRendererItem] = [:]

    private init() {}

    /// The renderer discovery modules this VLCKit has ("bonjour_renderer").
    public static var discoveryServices: [String] {
        (VLCRendererDiscoverer.list() ?? []).map(\.name)
    }

    /// Starts looking for devices (again calls do nothing).
    public func startSearching() {
        guard discoverers.isEmpty else { return }
        for name in Self.discoveryServices {
            guard let discoverer = VLCRendererDiscoverer(name: name) else { continue }
            let bridge = RendererBridge()
            discoverer.delegate = bridge
            guard discoverer.start() else { continue }
            discoverers.append((discoverer, bridge))
        }
        isSearching = !discoverers.isEmpty
    }

    /// Stops looking, unless something is playing on a device.
    public func stopSearching() {
        guard !isCasting else { return }
        for (discoverer, _) in discoverers {
            discoverer.stop()
        }
        discoverers = []
        targets = []
        items = [:]
        isSearching = false
    }

    /// Plays on `target`, or back on this device with `nil`.
    public func cast(to target: Target?) {
        guard target != activeTarget else { return }
        if let target, items[target.id] == nil { return }
        activeTarget = target
        onTargetChange?(target)
    }

    /// The renderer VLC sends to, for the engine.
    var activeRendererItem: VLCRendererItem? {
        activeTarget.flatMap { items[$0.id] }
    }

    fileprivate func added(_ item: VLCRendererItem) {
        let target = Self.target(for: item)
        items[target.id] = item
        guard !targets.contains(where: { $0.id == target.id }) else { return }
        targets.append(target)
        targets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    fileprivate func removed(_ item: VLCRendererItem) {
        let id = Self.target(for: item).id
        items[id] = nil
        targets.removeAll { $0.id == id }
        if activeTarget?.id == id {
            // The device went away: carry on here.
            activeTarget = nil
            onTargetChange?(nil)
        }
    }

    private static func target(for item: VLCRendererItem) -> Target {
        let flags = Int(item.flags)
        return Target(
            id: "\(item.type):\(item.name)",
            name: item.name,
            kind: item.type,
            playsVideo: flags & VLCRendererPlay.playsVideo.rawValue != 0,
            playsAudio: flags & VLCRendererPlay.playsAudio.rawValue != 0
        )
    }
}

/// A renderer discoverer's callbacks, from VLC's threads to the main actor.
private final class RendererBridge: NSObject, VLCRendererDiscovererDelegate, @unchecked Sendable {
    func rendererDiscovererItemAdded(_ rendererDiscoverer: VLCRendererDiscoverer, item: VLCRendererItem) {
        let box = RendererBox(item: item)
        Task { @MainActor in
            CastingCenter.shared.added(box.item)
        }
    }

    func rendererDiscovererItemDeleted(_ rendererDiscoverer: VLCRendererDiscoverer, item: VLCRendererItem) {
        let box = RendererBox(item: item)
        Task { @MainActor in
            CastingCenter.shared.removed(box.item)
        }
    }
}

private struct RendererBox: @unchecked Sendable {
    let item: VLCRendererItem
}
