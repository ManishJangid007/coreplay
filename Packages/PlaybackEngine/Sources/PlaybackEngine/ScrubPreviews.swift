import AVFoundation
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Observation
import PlaybackCore

/// YouTube-style frame previews above the scrubber.
///
/// Once a local video has been playing for a couple of seconds, frames are
/// made in the background, coarse to fine (see `ScrubPreviewPlan`), so a
/// nearby frame is ready almost at once and the strip fills in while the
/// video plays. Frames the user scrubs to are made next. AVFoundation makes
/// frames for the formats Apple opens; VLC's thumbnailer for the rest.
///
/// Finished strips are kept in the Caches folder, so a video watched again
/// previews instantly.
@MainActor
@Observable
public final class ScrubPreviews {
    /// How frames map to times; `nil` while the current item has none.
    public private(set) var plan: ScrubPreviewPlan?
    /// Bumped as frames arrive, so previews on screen refresh.
    public private(set) var revision = 0
    /// Width ÷ height of the frames.
    public private(set) var aspectRatio: Double = 16.0 / 9.0

    @ObservationIgnored private var frames: [Int: Data] = [:]
    @ObservationIgnored private var failed: Set<Int> = []
    @ObservationIgnored private var remaining: [Int] = []
    @ObservationIgnored private var wanted: [Int] = []
    @ObservationIgnored private var decoded: [Int: CGImage] = [:]
    @ObservationIgnored private var decodedOrder: [Int] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var itemID: UUID?

    /// Frames are this many pixels on their long side.
    nonisolated static let frameSize = 360
    /// Frames made per AVFoundation batch, between checks for frames the user is waiting for.
    nonisolated static let batchSize = 6

    public init() {}

    // MARK: Reading

    /// The frame for `time`: the exact one when it's ready, otherwise the
    /// nearest one that is. Asks for the exact frame to be made next.
    public func image(at time: TimeInterval) -> CGImage? {
        guard let plan else { return nil }
        let target = plan.index(for: time)
        if frames[target] == nil, !failed.contains(target), !wanted.contains(target) {
            wanted.append(target)
            if wanted.count > 4 {
                wanted.removeFirst(wanted.count - 4)
            }
        }
        guard let index = plan.nearest(to: target, where: { frames[$0] != nil }) else { return nil }
        return decodedImage(index)
    }

    /// `true` once every frame has been made (or tried).
    public var isComplete: Bool {
        guard let plan else { return false }
        return frames.count + failed.count >= plan.count
    }

    // MARK: Lifecycle (called by the controller)

    /// Starts previews for `item` if it's a local video and they aren't running already.
    func prepare(for item: PlaybackItem, duration: TimeInterval?, hasVideo: Bool) {
        guard itemID != item.id else { return }
        guard hasVideo, item.url.isFileURL, let duration, duration >= 10 else { return }
        reset()
        itemID = item.id
        let plan = ScrubPreviewPlan(duration: duration)
        self.plan = plan
        remaining = plan.generationOrder
        let url = item.url
        task = Task { [weak self] in
            // Let playback settle first: the first frame on screen matters more.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.run(url: url, plan: plan)
        }
    }

    /// Stops and forgets the current item's previews.
    func reset() {
        task?.cancel()
        task = nil
        itemID = nil
        plan = nil
        frames = [:]
        failed = []
        remaining = []
        wanted = []
        decoded = [:]
        decodedOrder = []
        aspectRatio = 16.0 / 9.0
        revision += 1
    }

    // MARK: Making frames

    private func run(url: URL, plan: ScrubPreviewPlan) async {
        let key = await ScrubPreviewCache.key(for: url, plan: plan)
        if let key, let cached = await ScrubPreviewCache.load(key: key), cached.plan == plan {
            guard self.plan == plan, !Task.isCancelled else { return }
            frames = cached.frames
            failed = Set((0..<plan.count).filter { cached.frames[$0] == nil })
            remaining = []
            wanted = []
            updateAspectRatio()
            revision += 1
            return
        }

        let usesAVFoundation = ContainerFormat(url: url).support == .native
        while !Task.isCancelled, self.plan == plan {
            let batch = nextBatch(size: usesAVFoundation ? Self.batchSize : 1)
            guard !batch.isEmpty else { break }
            let requests = batch.map { (index: $0, time: plan.time(of: $0)) }
            let results: [(index: Int, data: Data?)]
            if usesAVFoundation {
                results = await Self.avFrames(url: url, requests: requests, tolerance: plan.interval / 2)
            } else {
                var vlcResults: [(index: Int, data: Data?)] = []
                for request in requests {
                    let data = await FrameGrabber.shared.frameJPEG(from: url, at: request.time, maxPixelSize: Self.frameSize, precise: false)
                    vlcResults.append((request.index, data))
                }
                results = vlcResults
            }
            guard !Task.isCancelled, self.plan == plan else { return }
            for result in results {
                if let data = result.data {
                    frames[result.index] = data
                } else {
                    failed.insert(result.index)
                }
            }
            if frames.count <= Self.batchSize {
                updateAspectRatio()
            }
            revision += 1
        }

        guard !Task.isCancelled, self.plan == plan, let key, !frames.isEmpty else { return }
        let snapshot = ScrubPreviewCache.Entry(plan: plan, frames: frames)
        Task.detached(priority: .background) {
            ScrubPreviewCache.save(snapshot, key: key)
        }
    }

    /// Frames the user is waiting for first, then the coarse-to-fine order.
    private func nextBatch(size: Int) -> [Int] {
        var batch: [Int] = []
        while batch.count < size, let index = wanted.popLast() {
            if frames[index] == nil, !failed.contains(index), !batch.contains(index) {
                batch.append(index)
                remaining.removeAll { $0 == index }
            }
        }
        while batch.count < size, !remaining.isEmpty {
            let index = remaining.removeFirst()
            if frames[index] == nil, !failed.contains(index) {
                batch.append(index)
            }
        }
        return batch
    }

    private func updateAspectRatio() {
        guard let first = frames.keys.sorted().first, let image = decodedImage(first),
              image.width > 0, image.height > 0 else { return }
        aspectRatio = Double(image.width) / Double(image.height)
    }

    private func decodedImage(_ index: Int) -> CGImage? {
        if let image = decoded[index] {
            return image
        }
        guard let data = frames[index],
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        decoded[index] = image
        decodedOrder.append(index)
        if decodedOrder.count > 16 {
            decoded[decodedOrder.removeFirst()] = nil
        }
        return image
    }

    /// One AVFoundation generator for a batch of frames. Keyframe-near
    /// frames (within half a slot) are much faster than exact ones and
    /// plenty for previews.
    private nonisolated static func avFrames(url: URL, requests: [(index: Int, time: TimeInterval)], tolerance: TimeInterval) async -> [(index: Int, data: Data?)] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: frameSize, height: frameSize)
        let slack = CMTime(seconds: max(tolerance, 0.5), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = slack
        generator.requestedTimeToleranceAfter = slack
        var results: [(index: Int, data: Data?)] = []
        for request in requests {
            if Task.isCancelled { break }
            let time = CMTime(seconds: request.time, preferredTimescale: 600)
            if let (image, _) = try? await generator.image(at: time) {
                results.append((request.index, FrameGrabber.jpeg(image, quality: 0.72)))
            } else {
                results.append((request.index, nil))
            }
        }
        return results
    }
}

/// Finished preview strips, in Caches/Coreplay/Scrub Previews. Keyed by the
/// file's path, size and date, so an edited file gets new previews.
enum ScrubPreviewCache {
    struct Entry: Codable, Sendable {
        var plan: ScrubPreviewPlan
        var frames: [Int: Data]
    }

    static let version = 1
    /// The folder is trimmed back to this size, oldest strips first.
    static let sizeLimit = 300 * 1_024 * 1_024

    static var directory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return caches.appending(path: "Coreplay/Scrub Previews", directoryHint: .isDirectory)
    }

    static func key(for url: URL, plan: ScrubPreviewPlan) async -> String? {
        await Task.detached(priority: .utility) {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            let size = values.fileSize ?? 0
            let date = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let identity = "\(version)|\(url.standardizedFileURL.path)|\(size)|\(date)|\(plan.count)|\(plan.interval)"
            let digest = SHA256.hash(data: Data(identity.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }

    static func load(key: String) async -> Entry? {
        await Task.detached(priority: .utility) {
            guard let file = directory?.appending(path: "\(key).plist"),
                  let data = try? Data(contentsOf: file) else { return nil }
            // Touch the file so trimming keeps recently watched videos.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return try? PropertyListDecoder().decode(Entry.self, from: data)
        }.value
    }

    static func save(_ entry: Entry, key: String) {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(entry)
            try data.write(to: directory.appending(path: "\(key).plist"), options: .atomic)
            trim(directory)
        } catch {
            // Previews are a nicety; they'll be made again next time.
        }
    }

    private static func trim(_ directory: URL) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { file -> (url: URL, size: Int, date: Date)? in
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
            return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > sizeLimit else { return }
        entries.sort { $0.date < $1.date }
        for entry in entries where total > sizeLimit * 3 / 4 {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
