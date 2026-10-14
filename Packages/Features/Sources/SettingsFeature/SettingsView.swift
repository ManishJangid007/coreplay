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
                Form {
                    MetadataSettingsSection()
                    SubtitleSourcesSection()
                }
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
            SubtitleSourcesSection()
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
    @Environment(PlaybackSession.self) private var session
    @AppStorage(PlaybackPreferences.autoplaysNextEpisodeKey) private var autoplaysNextEpisode = true
    @AppStorage(PlaybackPreferences.playsPreviewsKey) private var playsPreviews = true
    @AppStorage(PlaybackPreferences.allowsVolumeBoostKey) private var allowsVolumeBoost = false
    @AppStorage(PlaybackPreferences.remembersFileOptionsKey) private var remembersFileOptions = true

    private var replayGain: ReplayGainSettings {
        session.controller.replayGain
    }

    private var trackPreferences: TrackPreferences {
        session.controller.trackPreferences
    }

    private func updateTrackPreferences(_ change: (inout TrackPreferences) -> Void) {
        var preferences = trackPreferences
        change(&preferences)
        session.setTrackPreferences(preferences)
    }

    /// The languages you use first, then the most common ones.
    private var languages: [String] {
        TrackPreferences.commonLanguages(first: Locale.preferredLanguages)
    }

    private static func languageName(_ code: String) -> String {
        MediaTrack.languageName(for: code) ?? code
    }

    private func updateReplayGain(_ change: (inout ReplayGainSettings) -> Void) {
        var settings = replayGain
        change(&settings)
        Task { await session.setReplayGain(settings) }
    }

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
        Section {
            Picker("Audio", selection: Binding(
                get: { trackPreferences.audioLanguage ?? "" },
                set: { code in updateTrackPreferences { $0.audioLanguage = code.isEmpty ? nil : code } }
            )) {
                Text("As the Video Says").tag("")
                ForEach(languages, id: \.self) { code in
                    Text(Self.languageName(code)).tag(code)
                }
            }
            Picker("Subtitles", selection: Binding(
                get: { trackPreferences.subtitles },
                set: { mode in updateTrackPreferences { $0.subtitles = mode } }
            )) {
                ForEach(TrackPreferences.Subtitles.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if trackPreferences.subtitles == .always || trackPreferences.subtitles == .foreignAudio {
                Picker("Subtitle Language", selection: Binding(
                    get: { trackPreferences.subtitleLanguage ?? "" },
                    set: { code in updateTrackPreferences { $0.subtitleLanguage = code.isEmpty ? nil : code } }
                )) {
                    Text("Same as Coreplay (\(Self.languageName(session.controller.appLanguage)))").tag("")
                    ForEach(languages, id: \.self) { code in
                        Text(Self.languageName(code)).tag(code)
                    }
                }
            }
            Toggle("Remember Options for Each File", isOn: $remembersFileOptions)
        } header: {
            Text("Languages")
        } footer: {
            Text("Videos start in your audio language when they have it. \u{201C}When the Audio Is in Another Language\u{201D} shows subtitles only when you\u{2019}d need them, and otherwise just the forced lines for signs and other languages. Remembered options (tracks, timing, shape, crop and turning) come back whenever you play that video again.")
        }
        Section {
            Picker("Sound Check", selection: Binding(
                get: { replayGain.mode },
                set: { mode in updateReplayGain { $0.mode = mode } }
            )) {
                ForEach(ReplayGainMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if replayGain.mode != .off {
                LabeledContent("Level") {
                    HStack {
                        Slider(value: Binding(
                            get: { replayGain.preamp },
                            set: { value in updateReplayGain { $0.preamp = (value * 2).rounded() / 2 } }
                        ), in: -6...6)
                        Text(Self.decibels(replayGain.preamp))
                            .monospacedDigit()
                            .frame(minWidth: 52, alignment: .trailing)
                    }
                }
                Toggle("Prevent Clipping", isOn: Binding(
                    get: { replayGain.preventsClipping },
                    set: { value in updateReplayGain { $0.preventsClipping = value } }
                ))
            }
            Toggle("Volume Boost", isOn: $allowsVolumeBoost)
        } header: {
            Text("Listening")
        } footer: {
            Text("Sound Check plays songs at the same loudness, using the ReplayGain values your tagger saved in them. Album keeps an album\u{2019}s quiet songs quieter than its loud ones. Volume Boost lets the volume go up to 200%; above 100%, playback moves to the VLC engine.")
        }
    }

    /// "+1.5 dB", "0 dB".
    private static func decibels(_ value: Double) -> String {
        let text = value.formatted(.number.precision(.fractionLength(0...1)))
        return value > 0 ? "+\(text) dB" : "\(text) dB"
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

        Section {
            Toggle("Look Up Lyrics", isOn: Binding(
                get: { library.looksUpLyrics },
                set: { library.setLooksUpLyrics($0) }
            ))
            Link("Lyrics from LRCLIB", destination: URL(string: "https://lrclib.net")!)
        } header: {
            Text("Lyrics")
        } footer: {
            Text("Songs without lyrics in their tags or an .lrc file beside them get synced lyrics from LRCLIB, which needs no account. The song\u{2019}s title, artist, album and length are sent.")
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

/// OpenSubtitles.com: your API key and, for downloads, your account.
private struct SubtitleSourcesSection: View {
    @Environment(PlaybackSession.self) private var session
    @State private var apiKey = ""
    @State private var username = ""
    @State private var password = ""
    @State private var problem: String?

    private var isConnected: Bool {
        session.onlineSubtitles != nil
    }

    var body: some View {
        Section {
            if isConnected {
                LabeledContent("OpenSubtitles") {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let credentials = OpenSubtitlesCredentials.load(), credentials.hasAccount {
                    LabeledContent("Account", value: credentials.username)
                }
                Button("Remove Key and Account", role: .destructive) {
                    OpenSubtitlesCredentials.delete()
                    session.onlineSubtitles = nil
                }
            } else {
                SecureField("API Key", text: $apiKey)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                TextField("Username (for downloads)", text: $username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Password", text: $password)
                Button("Save") {
                    save()
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                Link("Get an API Key from OpenSubtitles", destination: URL(string: "https://www.opensubtitles.com/en/consumers")!)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Subtitles Online")
        } footer: {
            Text("With your own OpenSubtitles.com key, the player\u{2019}s Subtitles page can search for subtitles and add them while you watch. Only the file\u{2019}s fingerprint, its title and your languages are sent. Downloads count against your account\u{2019}s daily allowance. The key and password stay in your Keychain.")
        }
    }

    private func save() {
        let credentials = OpenSubtitlesCredentials(apiKey: apiKey, username: username, password: password)
        do {
            try credentials.save()
            session.onlineSubtitles = OpenSubtitlesProvider(credentials: credentials)
            apiKey = ""
            username = ""
            password = ""
            problem = nil
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
