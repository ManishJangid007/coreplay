#if os(macOS)
import AppKit
import AVFoundation
import Foundation
import PlaybackCore
import Testing
import VLCKit
@testable import PlaybackEngine

/// Plays a small generated movie (H.264 and AAC) through each engine, in a
/// real window, and checks that it starts and its clock moves.
///
/// These caught a deadlock that kept every VLC movie on "loading": options
/// applied on the main thread just as libVLC created its video output, which
/// itself was waiting for the main thread. It shows up most when VideoToolbox
/// is already warm, hence VLC runs after an AVFoundation one, several times.
///
/// Each run writes what happened to `build/playback-trace.txt`, and VLC runs
/// write libVLC's log to `build/vlc-<run>.log`. If the main thread locks up,
/// a watchdog samples every thread into `build/hang-<run>.txt` and ends the
/// test process, so the build script carries on instead of hanging.
extension RealMediaTests {
    @MainActor
    @Suite("Playback smoke tests", .serialized)
    struct PlaybackSmokeTests {
        enum VLCSetup: String, CaseIterable, Sendable {
            /// A plain view as the drawable: no Picture in Picture hooks.
            case plainView = "plain-view"
            /// The controller's view, which offers VLC Picture in Picture.
            case pictureInPictureView = "pip-view"
            /// The controller's view, with every option set before play as the controller does.
            case pictureInPictureViewWithOptions = "pip-view-options"
        }

        @Test func controllerPlaysWithAVFoundation() async throws {
            try await playThroughController(.avFoundation)
        }

        @Test(arguments: 1...3)
        func controllerPlaysWithVLC(run: Int) async throws {
            try await playThroughController(.vlc, run: run)
        }

        /// Every option away from its default, set while the video opens, so
        /// they reach libVLC while it creates the video output.
        @Test func controllerPlaysWithVLCAndChosenOptions() async throws {
            try await playThroughController(.vlc, choosesOptions: true)
        }

        @Test(arguments: VLCSetup.allCases)
        func vlcEnginePlays(_ setup: VLCSetup) async throws {
            let name = "vlc-\(setup.rawValue)"
            let watchdog = Watchdog(name: name, limit: 30)
            defer { watchdog.finish() }
            let movie = try await TestMovie.url()

            let configuration = EngineConfiguration()
            let library = VLCLibraryProvider().library(options: configuration.libVLCLibraryOptions)
            let log = try VLCLogFile(name: name, library: library)
            defer { log.close() }
            let engine = VLCKitEngine(library: library, mediaOptions: configuration.libVLCMediaOptions)
            let view: PlatformVideoView = setup == .plainView ? PlatformVideoView(frame: .zero) : VideoHostView(frame: .zero)
            let window = TestWindow(showing: view)
            defer { window.close() }

            engine.attachVideoOutput(to: view)
            let events = engine.events
            let recorder = Task { @MainActor in
                for await event in events {
                    Trace.write("\(name): event \(event)")
                }
            }
            defer { recorder.cancel() }

            Trace.write("\(name): load")
            try await engine.load(PlaybackItem(url: movie, kind: .video, title: "Smoke"))
            if setup == .pictureInPictureViewWithOptions {
                engine.fillMode = .fit
                engine.aspectRatio = nil
                engine.cropRatio = nil
                engine.videoAdjustments = .neutral
                engine.deinterlace = .automatic
                engine.stereoMode = .automatic
                engine.equalizer = .flat
                engine.subtitleScale = 1
            }
            Trace.write("\(name): play")
            engine.play()
            let played = await waitUntil(seconds: 10, name: name, status: { "state \(engine.state)" }) {
                engine.state == .playing && engine.currentTime > 1
            }
            Trace.write("\(name): \(played ? "played" : "DID NOT PLAY"), state \(engine.state), time \(engine.currentTime)")
            #expect(played, "\(name): state \(engine.state), time \(engine.currentTime)")
            await engine.shutdown()
            Trace.write("\(name): shut down")
        }

        private func playThroughController(_ preference: EnginePreference, run: Int = 1, choosesOptions: Bool = false) async throws {
            let name = "controller-\(preference.rawValue)\(choosesOptions ? "-options" : "")-\(run)"
            let watchdog = Watchdog(name: name, limit: 30)
            defer { watchdog.finish() }
            let movie = try await TestMovie.url()

            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }

            Trace.write("\(name): load")
            await controller.load(PlaybackItem(url: movie, kind: .video, title: "Smoke", enginePreference: preference))
            Trace.write("\(name): load returned, engine \(String(describing: controller.activeEngine)), state \(controller.state)")
            if choosesOptions {
                controller.setFillMode(.fill)
                await controller.setAspectRatio(VideoRatio(4, 3))
                await controller.setCropRatio(VideoRatio(16, 9))
                await controller.setVideoAdjustments(VideoAdjustments(brightness: 1.2, contrast: 1.1, saturation: 1.3, hue: 10, gamma: 1.1))
                await controller.setDeinterlace(.on)
                await controller.setStereoMode(.mono)
                await controller.setEqualizer(EqualizerSettings(isEnabled: true, presetName: nil, preamp: 3, bands: [4, 3, 2, 1, 0, 0, 1, 2, 3, 4]))
                await controller.setSubtitleSize(.large)
                Trace.write("\(name): options chosen, state \(controller.state)")
            }
            let played = await waitUntil(seconds: 10, name: name, status: { "state \(controller.state), PiP possible \(controller.pictureInPicture.isPossible)" }) {
                controller.state == .playing && controller.currentTime > 1
            }
            Trace.write("\(name): \(played ? "played" : "DID NOT PLAY"), state \(controller.state), time \(controller.currentTime)")
            #expect(played, "\(name): state \(controller.state), time \(controller.currentTime)")
            #expect(controller.activeEngine == (preference == .vlc ? .vlc : .avFoundation))
            await controller.stop()
            Trace.write("\(name): stopped")
        }

        /// Polls `condition` every 50 ms, noting each new status in the trace.
        private func waitUntil(seconds: Double, name: String, status: () -> String, _ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            var lastStatus = ""
            while Date() < deadline {
                let current = status()
                if current != lastStatus {
                    Trace.write("\(name): \(current)")
                    lastStatus = current
                }
                if condition() {
                    return true
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return false
        }
    }
}

// MARK: - Test movie

/// A 320×180 movie at 30 frames a second: H.264 video with a white bar that
/// moves 4 pixels a frame (so a frame's time can be read back from it), and
/// a quiet AAC tone. Written once per length per test run.
@MainActor
enum TestMovie {
    private static var cached: [Int: URL] = [:]

    static let width = 320
    static let height = 180
    static let framesPerSecond = 30
    static let barWidth = 24

    enum Failure: Error {
        case writer(String)
    }

    static func url(seconds: Int = 6) async throws -> URL {
        if let url = cached[seconds], FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "coreplay-smoke-\(seconds)s-\(UUID().uuidString).mp4")
        try await write(to: url, seconds: seconds, width: width, height: height, pixelAspect: nil)
        cached[seconds] = url
        Trace.write("movie: wrote \(url.lastPathComponent)")
        return url
    }

    /// A two-second movie of another shape: `width` × `height` pixels, which
    /// with `pixelAspect` (horizontal ÷ vertical spacing) aren't square.
    static func shaped(width: Int, height: Int, pixelAspect: (Int, Int)? = nil) async throws -> URL {
        let name = "coreplay-shape-\(width)x\(height)-\(pixelAspect.map { "\($0.0)to\($0.1)" } ?? "square")-\(UUID().uuidString).mp4"
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try await write(to: url, seconds: 2, width: width, height: height, pixelAspect: pixelAspect)
        Trace.write("movie: wrote \(url.lastPathComponent)")
        return url
    }

    /// Where the bar's left edge is in `frame`.
    static func barStart(frame: Int) -> Int {
        (frame * 4) % (width - barWidth)
    }

    private static func write(to url: URL, seconds: Int, width: Int, height: Int, pixelAspect: (Int, Int)?) async throws {
        let framesPerSecond = Int32(Self.framesPerSecond)
        let sampleRate = 44_100

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        if let pixelAspect {
            videoSettings[AVVideoPixelAspectRatioKey] = [
                AVVideoPixelAspectRatioHorizontalSpacingKey: pixelAspect.0,
                AVVideoPixelAspectRatioVerticalSpacingKey: pixelAspect.1,
            ]
        }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 96_000,
        ])
        audio.expectsMediaDataInRealTime = false
        writer.add(video)
        writer.add(audio)
        guard writer.startWriting() else {
            throw Failure.writer(writer.error?.localizedDescription ?? "can't start")
        }
        writer.startSession(atSourceTime: .zero)

        // Feed whichever input is ready, so the writer can interleave the
        // two tracks as it likes, and finish each one when it runs out.
        let audioFormat = try makeAudioFormat(sampleRate: sampleRate)
        let samplesPerFrame = sampleRate / Int(framesPerSecond)
        let frameCount = seconds * Int(framesPerSecond)
        var videoFrame = 0
        var audioFrame = 0
        var idleRounds = 0
        while videoFrame < frameCount || audioFrame < frameCount {
            var progressed = false
            if videoFrame < frameCount, video.isReadyForMoreMediaData {
                guard let pool = adaptor.pixelBufferPool else { throw Failure.writer("no pixel buffer pool") }
                var pixelBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
                guard let pixelBuffer else { throw Failure.writer("no pixel buffer") }
                paint(pixelBuffer, frame: videoFrame, width: width, height: height)
                guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(videoFrame), timescale: framesPerSecond)) else {
                    throw Failure.writer(writer.error?.localizedDescription ?? "video append failed")
                }
                videoFrame += 1
                if videoFrame == frameCount {
                    video.markAsFinished()
                }
                progressed = true
            }
            if audioFrame < frameCount, audio.isReadyForMoreMediaData {
                let sample = try makeAudioSample(format: audioFormat, start: audioFrame * samplesPerFrame, count: samplesPerFrame, sampleRate: sampleRate)
                guard audio.append(sample) else {
                    throw Failure.writer(writer.error?.localizedDescription ?? "audio append failed")
                }
                audioFrame += 1
                if audioFrame == frameCount {
                    audio.markAsFinished()
                }
                progressed = true
            }
            if progressed {
                idleRounds = 0
                await Task.yield()
            } else {
                idleRounds += 1
                guard idleRounds < 2_500 else {
                    throw Failure.writer("inputs stopped accepting data (video \(videoFrame), audio \(audioFrame))")
                }
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            throw Failure.writer(writer.error?.localizedDescription ?? "didn't finish")
        }
    }

    /// A dark blue picture with a white bar that moves across it.
    private static func paint(_ buffer: CVPixelBuffer, frame: Int, width: Int, height: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        // The bar moves 4 pixels a frame, wrapping before the right edge.
        let start = (frame * 4) % max(width - barWidth, 1)
        let bar = min(barWidth, width)
        for y in 0..<height {
            // BGRA, little-endian: 0xAARRGGBB.
            let row = base.advanced(by: y * bytesPerRow)
            row.initializeMemory(as: UInt32.self, repeating: 0xFF20_3060, count: width)
            row.advanced(by: start * 4).initializeMemory(as: UInt32.self, repeating: 0xFFFF_FFFF, count: bar)
        }
    }

    private static func makeAudioFormat(sampleRate: Int) throws -> CMAudioFormatDescription {
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )
        guard status == noErr, let format else { throw Failure.writer("audio format \(status)") }
        return format
    }

    /// `count` frames of a quiet 440 Hz tone, starting at frame `start`.
    private static func makeAudioSample(format: CMAudioFormatDescription, start: Int, count: Int, sampleRate: Int) throws -> CMSampleBuffer {
        var pcm = [Int16](repeating: 0, count: count * 2)
        for index in 0..<count {
            let phase = 2 * Double.pi * 440 * Double(start + index) / Double(sampleRate)
            let value = Int16(sin(phase) * 2_000)
            pcm[2 * index] = value
            pcm[2 * index + 1] = value
        }
        let byteCount = pcm.count * MemoryLayout<Int16>.size
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &block
        )
        guard status == kCMBlockBufferNoErr, let block else { throw Failure.writer("audio block \(status)") }
        status = pcm.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard status == kCMBlockBufferNoErr else { throw Failure.writer("audio bytes \(status)") }
        var sample: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil,
            sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { throw Failure.writer("audio sample \(status)") }
        return sample
    }
}

// MARK: - Window, trace, watchdog, VLC log

/// A small on-screen window holding the video view, as the player would.
@MainActor
final class TestWindow {
    private let window: NSWindow

    init(showing view: NSView) {
        _ = NSApplication.shared
        window = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 320, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        window.contentView = content
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
    }
}

/// Appends timestamped lines to build/playback-trace.txt as they happen.
final class Trace: @unchecked Sendable {
    private static let shared = Trace()
    private let lock = NSLock()
    private var handle: FileHandle?
    private var started = Date()

    static var folder: URL {
        // Tests/PlaybackEngineTests/PlaybackSmokeTests.swift → repository root.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "build", directoryHint: .isDirectory)
    }

    static func write(_ line: String) {
        shared.append(line)
    }

    private func append(_ line: String) {
        lock.withLock {
            if handle == nil {
                // Appends: xcodebuild relaunches the tests after a crash, and
                // the earlier process's lines are the interesting ones.
                try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                let url = Self.folder.appending(path: "playback-trace.txt")
                if TestSession.isNew(marker: "playback-trace") {
                    // Left by an earlier test run: start again.
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: url)
                _ = try? handle?.seekToEnd()
                started = Date()
                handle?.write(Data("--- test process \(ProcessInfo.processInfo.processIdentifier) at \(Date()) ---\n".utf8))
            }
            let stamp = String(format: "%7.2f", Date().timeIntervalSince(started))
            handle?.write(Data("\(stamp)  \(line)\n".utf8))
            try? handle?.synchronize()
        }
    }
}

/// Notices a main thread that stops responding, and ends the process if a
/// run takes far too long, so a deadlock can't stall the build script.
final class Watchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPing = Date()
    private var isFinished = false

    init(name: String, limit: TimeInterval) {
        let thread = Thread { [self] in
            let started = Date()
            var reported = false
            var sampled = false
            while !self.finished {
                Thread.sleep(forTimeInterval: 0.25)
                DispatchQueue.main.async { self.ping() }
                let silence = Date().timeIntervalSince(self.pinged)
                if silence > 2, !reported {
                    Trace.write("\(name): MAIN THREAD BLOCKED (no response for \(Int(silence)) s)")
                    reported = true
                } else if silence < 1 {
                    reported = false
                }
                if silence > 4, !sampled {
                    sampled = true
                    Watchdog.sample(into: Trace.folder.appending(path: "hang-\(name).txt"))
                    Trace.write("\(name): sampled the stuck process into build/hang-\(name).txt")
                }
                if Date().timeIntervalSince(started) > limit {
                    Trace.write("\(name): WATCHDOG gave up after \(Int(limit)) s; ending the test process")
                    exit(3)
                }
            }
        }
        thread.start()
    }

    func finish() {
        lock.withLock { isFinished = true }
    }

    /// Every thread's stack, from /usr/bin/sample, for working out a deadlock.
    static func sample(into file: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "2", "-mayDie", "-file", file.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Trace.write("sample failed: \(error.localizedDescription)")
        }
    }

    private var finished: Bool { lock.withLock { isFinished } }
    private var pinged: Date { lock.withLock { lastPing } }

    private func ping() {
        lock.withLock { lastPing = Date() }
    }
}

/// libVLC's own log for one run, in build/vlc-<name>.log.
@MainActor
final class VLCLogFile {
    private let handle: FileHandle
    private let library: VLCLibrary

    init(name: String, library: VLCLibrary) throws {
        let url = Trace.folder.appending(path: "vlc-\(name).log")
        try FileManager.default.createDirectory(at: Trace.folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        self.library = library
        let logger = VLCFileLogger(fileHandle: handle)
        logger.level = .debug
        library.loggers = [logger]
    }

    func close() {
        library.loggers = nil
        try? handle.close()
    }
}

/// One `xcodebuild test` run. It relaunches the test process after a crash,
/// so files that collect results append within a run and start afresh in the
/// next one: the run is told apart by xcodebuild's process ID.
enum TestSession {
    static func isNew(marker name: String) -> Bool {
        let marker = Trace.folder.appending(path: ".\(name).session")
        let session = "\(getppid())"
        let previous = try? String(contentsOf: marker, encoding: .utf8)
        guard previous != session else { return false }
        try? FileManager.default.createDirectory(at: Trace.folder, withIntermediateDirectories: true)
        try? Data(session.utf8).write(to: marker)
        return true
    }
}
#endif
