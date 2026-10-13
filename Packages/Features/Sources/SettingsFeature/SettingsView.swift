import DesignSystem
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// Settings, grouped as Apple would: a `Form` on iOS and a tabbed `Settings`
/// scene on the Mac. Only settings that do something today are shown; the
/// rest of the plan's groups (Audio, Subtitles, Metadata, Privacy and Lock)
/// appear as their features land.
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

    var body: some View {
        Section {
            Toggle("Hardware Decoding", isOn: $settings.hardwareDecoding)
        } header: {
            Text("Video")
        } footer: {
            Text("Uses the media engine in your device\u{2019}s chip for smoother playback and longer battery life. Turn off if a video shows artifacts. Applies to the next file you open.")
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
