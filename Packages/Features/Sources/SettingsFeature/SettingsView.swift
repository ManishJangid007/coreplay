import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// Settings, grouped as Apple would: a `Form` on iOS and a tabbed `Settings`
/// scene on the Mac. Only settings that do something today are shown; the
/// rest of the plan's groups (Audio, Subtitles, Privacy and Lock) appear as
/// their features land.
public struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    public init() {}

    public var body: some View {
        #if os(macOS)
        TabView {
            Tab("Playback", systemImage: "play.rectangle") {
                Form { PlaybackSettingsSection(settings: settings) }
                    .formStyle(.grouped)
            }
            Tab("Metadata", systemImage: "film.stack") {
                Form { MetadataSettingsSection() }
                    .formStyle(.grouped)
            }
            Tab("Network", systemImage: "network") {
                Form { NetworkSettingsSection(settings: settings) }
                    .formStyle(.grouped)
            }
            Tab("Advanced", systemImage: "gearshape.2") {
                Form { AdvancedSettingsSection(settings: settings) }
                    .formStyle(.grouped)
            }
            Tab("About", systemImage: "info.circle") {
                NavigationStack {
                    Form { AboutSection() }
                        .formStyle(.grouped)
                }
            }
        }
        .frame(width: 520, height: 420)
        #else
        Form {
            PlaybackSettingsSection(settings: settings)
            MetadataSettingsSection()
            NetworkSettingsSection(settings: settings)
            AdvancedSettingsSection(settings: settings)
            AboutSection()
        }
        .navigationTitle("Settings")
        #endif
    }
}

private struct PlaybackSettingsSection: View {
    @Bindable var settings: AppSettings
    @AppStorage(PlaybackPreferences.autoplaysNextEpisodeKey) private var autoplaysNextEpisode = true
    @AppStorage(PlaybackPreferences.playsPreviewsKey) private var playsPreviews = true

    var body: some View {
        Section {
            Toggle("Hardware Decoding", isOn: $settings.hardwareDecoding)
        } header: {
            Text("Video")
        } footer: {
            Text("Uses the media engine in your device\u{2019}s chip for smoother playback and longer battery life. Turn off if a video shows artifacts. Applies to the next file you open.")
        }
        Section {
            Toggle("Play Next Episode Automatically", isOn: $autoplaysNextEpisode)
            Toggle("Play Previews", isOn: $playsPreviews)
        } header: {
            Text("Watching")
        } footer: {
            Text("When an episode\u{2019}s end credits start, the next one plays after a short countdown. Previews play a few silent seconds of a movie behind its title at the top of Home, Movies and TV Shows.")
        }
    }
}

/// The user's TMDB key, for posters, synopses, cast and episode titles, and
/// the free sources used without one.
private struct MetadataSettingsSection: View {
    @Environment(LibraryManager.self) private var library
    @State private var key = ""
    @State private var isSaving = false
    @State private var problem: String?

    var body: some View {
        Section {
            if library.hasMetadataKey {
                LabeledContent("TMDB") {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("Look Up Unmatched Titles Again") {
                    library.lookUpUnmatchedAgain()
                }
                Button("Remove Key", role: .destructive) {
                    library.removeMetadataKey()
                }
            } else {
                SecureField("API Key or Read Access Token", text: $key)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { Task { await save() } }
                HStack {
                    Button("Save Key") {
                        Task { await save() }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Link("Get a Free Key from TMDB", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
            }
            if let message = problem ?? library.metadataProblem {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Movie and TV Details")
        } footer: {
            Text("Coreplay names movies and episodes from their files and any .nfo files beside them. With your own TMDB key it also fetches posters, backdrops, synopses, cast and episode titles. Only titles and years are sent, and the key stays in your Keychain. This product uses the TMDB API but is not endorsed or certified by TMDB.")
        }

        Section {
            Toggle("Look Up Without a Key", isOn: Binding(
                get: { library.usesFreeMetadataSources },
                set: { library.setUsesFreeMetadataSources($0) }
            ))
            if library.usesFreeMetadataSources, !library.hasMetadataKey {
                Button("Look Up Unmatched Titles Again") {
                    library.lookUpUnmatchedAgain()
                }
            }
            Link("TV details from TVmaze", destination: URL(string: "https://www.tvmaze.com")!)
            Link("Movie details from Wikipedia", destination: URL(string: "https://en.wikipedia.org")!)
        } header: {
            Text("Free Sources")
        } footer: {
            Text("Without a TMDB key, Coreplay gets show posters, episode titles and stills from TVmaze, and movie posters and synopses from Wikipedia. Neither needs an account. Wikipedia\u{2019}s posters are small, so a TMDB key gives sharper artwork; once you add one, TMDB takes over. Only titles and years are sent. TVmaze and Wikipedia text is shared under CC BY-SA 4.0.")
        }
    }

    private func save() async {
        isSaving = true
        problem = nil
        defer { isSaving = false }
        do {
            try await library.setMetadataKey(key)
            key = ""
        } catch {
            problem = error.localizedDescription
        }
    }
}

private struct NetworkSettingsSection: View {
    @Bindable var settings: AppSettings
    private let cachingChoices = [300, 1_000, 3_000, 5_000, 10_000]

    var body: some View {
        Section {
            Picker("Stream Buffer", selection: $settings.networkCachingMilliseconds) {
                ForEach(cachingChoices, id: \.self) { value in
                    Text(label(for: value)).tag(value)
                }
            }
        } header: {
            Text("Network")
        } footer: {
            Text("How much of a network stream is loaded before playback starts. A larger buffer helps on slow or unreliable connections.")
        }
    }

    private func label(for milliseconds: Int) -> String {
        milliseconds < 1_000 ? "\(milliseconds) ms" : "\(milliseconds / 1_000) s"
    }
}

private struct AdvancedSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            Toggle("Always Use VLC Engine", isOn: $settings.alwaysUseVLC)
            VStack(alignment: .leading, spacing: 6) {
                Text("Custom libVLC Options")
                TextField("--option=value :media-option=value", text: $settings.customLibVLCOptions, axis: .vertical)
                    .font(.body.monospaced())
                    .lineLimit(2...5)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Coreplay normally plays files Apple supports with AVFoundation and everything else with VLC. Options starting with \u{201C}--\u{201D} apply to the VLC engine; options starting with \u{201C}:\u{201D} apply to each file. Changes apply to the next file you open.")
        }
    }
}

private struct AboutSection: View {
    @Environment(PlaybackSession.self) private var session
    @State private var vlcVersion = ""

    var body: some View {
        Section("About") {
            HStack(spacing: 14) {
                BrandLogo(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Brand.appName)
                        .font(.headline)
                    Text("VLC\u{2019}s engine, Apple\u{2019}s experience, your library.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            LabeledContent("Version", value: Self.appVersion)
            LabeledContent("VLCKit", value: EngineVersions.vlcKit)
            LabeledContent("libVLC", value: vlcVersion.isEmpty ? "\u{2014}" : vlcVersion)
            NavigationLink("Acknowledgements") {
                AcknowledgementsView()
            }
        }
        .task {
            vlcVersion = session.controller.vlcVersionDescription
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
