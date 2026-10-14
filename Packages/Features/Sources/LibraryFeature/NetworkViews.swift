import DesignSystem
import Networking
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI

/// A folder on a share, to browse: where it is, what to call it, and the
/// saved server it belongs to (for its login).
public struct NetworkPlace: Hashable, Sendable {
    public var url: URL
    public var title: String
    public var serverID: UUID?

    public init(url: URL, title: String, serverID: UUID? = nil) {
        self.url = url
        self.title = title
        self.serverID = serverID
    }
}

// MARK: - The Network section of Sources

/// Saved servers, servers found on the network, Connect to Server and
/// Open Network Stream, in the same settings-style list as the folders.
struct NetworkSourcesSection: View {
    @Environment(\.appActions) private var actions
    @Binding var isConnecting: Bool
    @Binding var editing: SavedServer?
    @State private var pendingRemoval: SavedServer?

    var body: some View {
        let store = NetworkStore.shared
        let found = NetworkDiscovery.shared.servers.filter { server in
            !store.servers.contains { $0.contains(server.url) }
        }
        Section {
            ForEach(store.servers) { server in
                if let url = server.url {
                    NavigationLink(value: NetworkPlace(url: url, title: server.displayName, serverID: server.id)) {
                        NetworkServerRow(
                            title: server.displayName,
                            detail: server.summary + (server.user.map { " \u{00B7} \($0)" } ?? ""),
                            systemImage: server.networkProtocol.systemImage
                        )
                    }
                    .contextMenu {
                        Button("Edit\u{2026}", systemImage: "pencil") { editing = server }
                        Button("Forget Server\u{2026}", systemImage: "minus.circle", role: .destructive) { pendingRemoval = server }
                    }
                    #if os(iOS)
                    .swipeActions(edge: .trailing) {
                        Button("Forget", systemImage: "minus.circle", role: .destructive) { pendingRemoval = server }
                        Button("Edit", systemImage: "pencil") { editing = server }
                    }
                    #endif
                }
            }
            ForEach(found) { server in
                NavigationLink(value: NetworkPlace(url: server.url, title: server.name)) {
                    NetworkServerRow(
                        title: server.name,
                        detail: "\(server.networkProtocol?.title ?? (server.url.scheme ?? "").uppercased()) \u{00B7} on this network",
                        systemImage: server.networkProtocol?.systemImage ?? "network"
                    )
                }
            }
            Button {
                isConnecting = true
            } label: {
                Label("Connect to Server\u{2026}", systemImage: "plus.circle")
            }
            Button {
                actions.openStream()
            } label: {
                Label("Open Network Stream\u{2026}", systemImage: "antenna.radiowaves.left.and.right")
            }
        } header: {
            Text("Network")
        } footer: {
            Text("Shared folders, media servers and streams play straight from the network. Logins are kept in the Keychain.")
        }
        .confirmationDialog(
            "Forget \u{201C}\(pendingRemoval?.displayName ?? "")\u{201D}?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Forget Server", role: .destructive) {
                if let server = pendingRemoval {
                    if let url = server.url {
                        NetworkKeychain.delete(for: url, user: server.user)
                    }
                    NetworkStore.shared.remove(server)
                }
                pendingRemoval = nil
            }
        } message: {
            Text("Its login is removed from the Keychain too.")
        }
    }
}

private struct NetworkServerRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Connect to Server

/// Adds a share (or edits a saved one): its type, address and login. The
/// folder is opened before the server is kept, so mistakes show here.
struct ConnectToServerView: View {
    @Environment(\.dismiss) private var dismiss
    let existing: SavedServer?
    let onConnected: (SavedServer) -> Void

    @State private var networkProtocol: NetworkProtocol = .smb
    @State private var address = ""
    @State private var name = ""
    @State private var user = ""
    @State private var password = ""
    @State private var domain = ""
    @State private var remember = true
    @State private var isConnecting = false
    @State private var problem: String?

    private var parsed: NetworkAddress.Parsed? {
        NetworkAddress.parse(address, defaultProtocol: networkProtocol)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $networkProtocol) {
                        ForEach(NetworkProtocol.connectable) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Address", text: $address, prompt: Text(placeholder))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .onSubmit { connect() }
                } footer: {
                    Text(networkProtocol.detail)
                }
                if networkProtocol.usesLogin {
                    Section {
                        TextField("User Name", text: $user)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                        if networkProtocol.usesDomain {
                            TextField("Domain or Workgroup", text: $domain, prompt: Text("Optional"))
                                .autocorrectionDisabled()
                        }
                        Toggle("Remember Password in Keychain", isOn: $remember)
                    } header: {
                        Text("Login")
                    } footer: {
                        Text("Leave the user name empty to connect as a guest.")
                    }
                }
                Section {
                    TextField("Name", text: $name, prompt: Text("Optional"))
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isConnecting)
            .navigationTitle(existing == nil ? "Connect to Server" : "Edit Server")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(existing == nil ? "Connect" : "Save") { connect() }
                            .disabled(parsed == nil)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 420)
        #endif
        .onAppear(perform: fillIn)
        .onChange(of: address) { _, text in
            // Typing "sftp://…" picks SFTP.
            if let range = text.range(of: "://"), let typed = NetworkProtocol(scheme: String(text[..<range.lowerBound])),
               typed != networkProtocol, NetworkProtocol.connectable.contains(typed) {
                networkProtocol = typed
            }
        }
    }

    private var placeholder: String {
        switch networkProtocol {
        case .smb: "nas.local/Movies"
        case .sftp: "server.example.com/home/me"
        case .ftp: "ftp.example.com"
        case .nfs: "nas.local/export/media"
        case .upnp: ""
        }
    }

    private func fillIn() {
        guard let existing else { return }
        networkProtocol = existing.networkProtocol
        address = existing.host + (existing.port.map { ":\($0)" } ?? "") + existing.path
        name = existing.name
        user = existing.user ?? ""
        domain = existing.domain ?? ""
        if let url = existing.url, let saved = NetworkKeychain.credential(for: url, user: existing.user) {
            password = saved.password
        }
    }

    private func connect() {
        guard let parsed, let url = parsed.url, !isConnecting else { return }
        let userName = user.trimmingCharacters(in: .whitespaces).isEmpty ? (parsed.user ?? "") : user.trimmingCharacters(in: .whitespaces)
        let credential = userName.isEmpty || !networkProtocol.usesLogin
            ? nil
            : NetworkCredential(user: userName, password: password, domain: domain)
        isConnecting = true
        problem = nil
        Task {
            do {
                // Opened without VLC's own login prompt: a wrong password is
                // reported here, under the fields.
                _ = try await NetworkBrowser.shared.contents(of: url, credential: credential, asksForLogin: false)
                let server = SavedServer(
                    id: existing?.id ?? UUID(),
                    name: name,
                    networkProtocol: parsed.networkProtocol,
                    host: parsed.host,
                    port: parsed.port,
                    path: parsed.path,
                    user: credential?.user,
                    domain: credential?.domain
                )
                if let credential, remember {
                    NetworkKeychain.save(credential, for: url)
                } else if let previous = existing, let previousURL = previous.url {
                    NetworkKeychain.delete(for: previousURL, user: previous.user)
                }
                NetworkStore.shared.save(server)
                isConnecting = false
                dismiss()
                onConnected(server)
            } catch {
                isConnecting = false
                problem = credential == nil
                    ? "\(error.localizedDescription) If the server needs a login, enter it above."
                    : "\(error.localizedDescription) Check the user name and password."
            }
        }
    }
}

// MARK: - A folder on a share

/// What's in a folder on a share: folders to open, and videos and songs
/// that play straight from the network (subtitle files beside a video
/// come with it).
struct NetworkFolderView: View {
    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let place: NetworkPlace
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    @State private var entries: [NetworkEntry] = []
    @State private var phase: Phase = .loading
    @State private var filter = ""

    private var visible: [NetworkEntry] {
        let text = filter.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        content
            .navigationTitle(place.title)
            .searchable(text: $filter, prompt: "Filter")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if entries.contains(where: \.isPlayable) {
                        Button("Play All", systemImage: "play.fill") {
                            playAll()
                        }
                    }
                    Button("Reload", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                    .disabled(phase == .loading)
                }
            }
            .task(id: place) {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Opening \(place.title)\u{2026}")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Can\u{2019}t Open \u{201C}\(place.title)\u{201D}", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await load() }
                }
            }
        case .loaded:
            if entries.isEmpty {
                ContentUnavailableView("Nothing Here", systemImage: "folder", description: Text("This folder is empty."))
            } else {
                List(visible) { entry in
                    row(for: entry)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: NetworkEntry) -> some View {
        if entry.isFolder {
            NavigationLink(value: NetworkPlace(url: entry.url, title: entry.name, serverID: place.serverID)) {
                NetworkEntryRow(entry: entry)
            }
        } else if entry.isPlayable {
            Button {
                play(entry)
            } label: {
                NetworkEntryRow(entry: entry, resumePosition: entry.kind == .video ? NetworkStore.shared.resumePosition(for: entry.url) : nil)
            }
            .buttonStyle(.plain)
        } else {
            NetworkEntryRow(entry: entry)
                .opacity(0.5)
        }
    }

    private func load() async {
        phase = .loading
        let server = place.serverID.flatMap { id in NetworkStore.shared.servers.first { $0.id == id } }
        let credential = NetworkKeychain.credential(for: place.url, user: server?.user)
        do {
            entries = try await NetworkBrowser.shared.contents(of: place.url, credential: credential)
            phase = .loaded
        } catch {
            entries = []
            phase = .failed(error.localizedDescription)
        }
    }

    /// Plays `entry` and queues the rest of the folder's videos (or songs)
    /// after it, as a season or an album.
    private func play(_ entry: NetworkEntry) {
        let list = entries.filter { $0.kind == entry.kind }
        let index = list.firstIndex(of: entry) ?? 0
        let items = list.map { file in
            var item = PlaybackItem(
                url: file.url,
                kind: file.kind == .audio ? .audio : .video,
                externalSubtitleURLs: NetworkEntry.subtitles(for: file, in: entries)
            )
            if file == entry, file.kind == .video {
                item.startPosition = NetworkStore.shared.resumePosition(for: file.url)
            }
            return item
        }
        Task {
            await session.play(items, startingAt: index)
        }
        if entry.kind == .video {
            actions.showPlayer()
        }
    }

    private func playAll() {
        let videos = entries.filter { $0.kind == .video }
        if let first = videos.first {
            play(first)
        } else if let first = entries.first(where: { $0.kind == .audio }) {
            play(first)
        }
    }
}

private struct NetworkEntryRow: View {
    let entry: NetworkEntry
    var resumePosition: TimeInterval?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(entry.isFolder ? Color.accentColor : (entry.isPlayable ? Color.primary : Color.secondary))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .lineLimit(2)
                if let details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let resumePosition {
                Text("Resume \(Self.clock(resumePosition))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch entry.kind {
        case .folder: "folder.fill"
        case .video: "film"
        case .audio: "music.note"
        case .subtitle: "captions.bubble"
        case .playlist: "music.note.list"
        case .image: "photo"
        case .other: "doc"
        }
    }

    private var details: String? {
        var parts: [String] = []
        if let size = entry.size, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let modified = entry.modified {
            parts.append(modified.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3_600
        let minutes = total / 60 % 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Open Network Stream

/// A stream address to play (HTTP, HLS, DASH, RTSP, RTMP, RTP/UDP, MMS,
/// SRT, or a file on a share), and the streams opened before.
public struct OpenStreamView: View {
    @Environment(\.dismiss) private var dismiss
    private let onOpen: (URL) -> Void
    @State private var text = ""

    public init(onOpen: @escaping (URL) -> Void) {
        self.onOpen = onOpen
    }

    public var body: some View {
        let store = NetworkStore.shared
        let url = StreamAddress.url(from: text)
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $text, prompt: Text("https://example.com/live/index.m3u8"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .onSubmit {
                            if let url { open(url) }
                        }
                    if let url {
                        LabeledContent("Kind", value: StreamAddress.kind(of: url).title)
                    } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("That doesn\u{2019}t look like a stream address.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("HTTP and HTTPS, HLS, MPEG-DASH, RTSP, RTMP, RTP and UDP multicast, MMS and SRT. Settings \u{25B8} Network \u{25B8} Stream Buffer sets how much is loaded before playing.")
                }
                if !store.recentStreams.entries.isEmpty {
                    Section("Recent") {
                        ForEach(store.recentStreams.entries) { entry in
                            Button {
                                open(entry.url)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(StreamAddress.title(for: entry.url))
                                        .foregroundStyle(.primary)
                                    Text(entry.url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove from Recent", systemImage: "minus.circle") {
                                    store.forgetStream(entry.url)
                                }
                            }
                        }
                        Button("Clear Recent Streams", role: .destructive) {
                            store.forgetAllStreams()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Open Network Stream")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") {
                        if let url { open(url) }
                    }
                    .disabled(url == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 360)
        #endif
    }

    private func open(_ url: URL) {
        dismiss()
        onOpen(url)
    }
}
