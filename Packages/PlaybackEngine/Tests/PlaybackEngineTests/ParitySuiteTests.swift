#if os(macOS)
import Foundation
import PlaybackCore
import Testing
@testable import PlaybackEngine

/// The VLC parity suite: every sample in Tests/ParitySamples (see
/// Tools/make_parity_samples.py) is played the way the app plays it, through
/// the controller and its router, and what the engine reports is checked
/// against what FFmpeg wrote. Results go to build/parity-report.md.
extension RealMediaTests {
    @MainActor
    @Suite("Parity suite", .serialized)
    struct ParitySuiteTests {
        @Test(arguments: ParitySamples.all)
        func samplePlaysAndReportsItsStreams(_ sample: ParitySamples.Sample) async throws {
            let name = "parity-\(sample.file)"
            let watchdog = Watchdog(name: name, limit: 25)
            defer { watchdog.finish() }

            let url = ParitySamples.folder.appending(path: sample.file)
            let subtitles = (sample.externalSubtitles ?? []).map { ParitySamples.folder.appending(path: $0) }
            let item = PlaybackItem(url: url, title: sample.file, externalSubtitleURLs: subtitles)

            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }
            await controller.load(item)

            let expectedAudio = sample.streams.filter { $0.kind == "audio" }
            let expectedSubtitles = sample.streams.filter { $0.kind == "subtitle" }.count + subtitles.count
            let expectedVideo = sample.streams.first { $0.kind == "video" }

            // Playing, the clock moving, and (given a moment) every track listed.
            var played = false
            var settled = false
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                played = played || (controller.state == .playing && controller.currentTime > 0.2)
                settled = controller.audioTracks.count >= expectedAudio.count
                    && controller.subtitleTracks.count >= expectedSubtitles
                    && (expectedVideo == nil || controller.videoDimensions != nil)
                    && controller.chapters.count >= sample.chapters
                if played, settled {
                    break
                }
                try await Task.sleep(for: .milliseconds(50))
            }

            var problems: [String] = []
            if !played {
                problems.append("didn't play (state \(controller.state))")
            }
            if let duration = controller.duration {
                if abs(duration - sample.duration) > 0.5 {
                    problems.append("length \(String(format: "%.2f", duration)) s, expected \(sample.duration) s")
                }
            } else {
                problems.append("no length")
            }
            if let video = expectedVideo, let width = video.width, let height = video.height {
                if let dimensions = controller.videoDimensions {
                    if dimensions.width != width || dimensions.height != height {
                        problems.append("picture \(dimensions.width)×\(dimensions.height), expected \(width)×\(height)")
                    }
                } else {
                    problems.append("no picture size")
                }
            }
            if controller.audioTracks.count != expectedAudio.count {
                problems.append("\(controller.audioTracks.count) audio tracks, expected \(expectedAudio.count)")
            } else {
                for (track, expected) in zip(controller.audioTracks, expectedAudio) {
                    if let language = expected.language, !MediaTrack.languagesMatch(track.languageCode, language) {
                        problems.append("audio language \(track.languageCode ?? "none"), expected \(language)")
                    }
                }
            }
            if controller.subtitleTracks.count != expectedSubtitles {
                problems.append("\(controller.subtitleTracks.count) subtitle tracks, expected \(expectedSubtitles)")
            }
            if controller.chapters.count != sample.chapters {
                problems.append("\(controller.chapters.count) chapters, expected \(sample.chapters)")
            }

            let engine = controller.activeEngine.map { $0 == .vlc ? "vlc" : "avFoundation" } ?? "none"
            let engineNote = engine == sample.engine ? engine : "\(engine) (expected \(sample.engine))"
            ParityReport.add(
                sample: sample.file,
                covers: sample.covers.joined(separator: "; "),
                engine: engineNote,
                problems: problems,
                details: Self.details(controller)
            )
            #expect(problems.isEmpty, "\(sample.file): \(problems.joined(separator: "; "))")
            await controller.stop()
        }

        private static func details(_ controller: PlaybackController) -> String {
            var parts: [String] = []
            if let dimensions = controller.videoDimensions {
                parts.append("\(dimensions.width)×\(dimensions.height)")
            }
            let audio = controller.audioTracks.map { $0.displayName(locale: Locale(identifier: "en_US")) }
            if !audio.isEmpty {
                parts.append("audio: " + audio.joined(separator: ", "))
            }
            let subtitles = controller.subtitleTracks.map { $0.displayName(locale: Locale(identifier: "en_US")) }
            if !subtitles.isEmpty {
                parts.append("subtitles: " + subtitles.joined(separator: ", "))
            }
            if !controller.chapters.isEmpty {
                parts.append("chapters: " + controller.chapters.map(\.displayTitle).joined(separator: ", "))
            }
            return parts.joined(separator: "; ")
        }
    }
}

/// Tests/ParitySamples/manifest.json, written by Tools/make_parity_samples.py.
enum ParitySamples {
    struct Stream: Decodable, Sendable {
        let kind: String
        let codec: String?
        let language: String?
        let title: String?
        let width: Int?
        let height: Int?
        let transfer: String?
        let channels: Int?
        let sampleRate: Int?
    }

    struct Sample: Decodable, Sendable, CustomTestStringConvertible {
        let file: String
        let engine: String
        let covers: [String]
        let duration: Double
        let streams: [Stream]
        let chapters: Int
        let externalSubtitles: [String]?

        var testDescription: String { file }
    }

    struct Manifest: Decodable {
        let samples: [Sample]
    }

    static var folder: URL {
        // Packages/PlaybackEngine/Tests/PlaybackEngineTests/ParitySuiteTests.swift → repository root.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Tests/ParitySamples", directoryHint: .isDirectory)
    }

    static var all: [Sample] {
        guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.samples
    }
}

/// build/parity-report.md: one row per sample, started afresh each build.
final class ParityReport: @unchecked Sendable {
    private static let shared = ParityReport()
    private let lock = NSLock()

    static func add(sample: String, covers: String, engine: String, problems: [String], details: String) {
        shared.append(sample: sample, covers: covers, engine: engine, problems: problems, details: details)
    }

    private func append(sample: String, covers: String, engine: String, problems: [String], details: String) {
        lock.withLock {
            let url = Trace.folder.appending(path: "parity-report.md")
            if TestSession.isNew(marker: "parity-report") || !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.createDirectory(at: Trace.folder, withIntermediateDirectories: true)
                let header = """
                # Parity report

                Every sample in Tests/ParitySamples, played through the app's controller (written by ParitySuiteTests).

                | Sample | Covers | Engine | Result | What the engine reported |
                | --- | --- | --- | --- | --- |

                """
                try? Data(header.utf8).write(to: url)
            }
            let result = problems.isEmpty ? "OK" : "**" + problems.joined(separator: "; ") + "**"
            let row = "| \(sample) | \(covers) | \(engine) | \(result) | \(details) |\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                handle.write(Data(row.utf8))
                try? handle.close()
            }
        }
    }
}
#endif
