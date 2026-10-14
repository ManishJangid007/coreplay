#if os(macOS)
import Darwin
import Foundation

// Two small servers for the network tests, serving a folder on 127.0.0.1:
// FTP (with a login, the way VLC's ftp module talks) and HTTP (with byte
// ranges and keep-alive, the way AVPlayer and VLC fetch). Blocking sockets
// on their own threads: simple, and nothing here touches the main thread.

/// A socket helper: listening, accepting with a timeout, and whole writes.
enum TestSocket {
    /// Listens on 127.0.0.1 and an ephemeral port.
    static func listen() -> (fd: Int32, port: UInt16)? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 16) == 0 else {
            close(fd)
            return nil
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        return (fd, UInt16(bigEndian: address.sin_port))
    }

    /// Accepts one connection, or gives up after `timeout` seconds.
    static func accept(_ listener: Int32, timeout: Int32 = 10) -> Int32? {
        var poller = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        guard poll(&poller, 1, timeout * 1_000) > 0 else { return nil }
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { return nil }
        var one: Int32 = 1
        // A client that hangs up mid-transfer mustn't kill the test process.
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    @discardableResult
    static func write(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let sent = send(fd, buffer.baseAddress! + offset, buffer.count - offset, 0)
                guard sent > 0 else { return false }
                offset += sent
            }
            return true
        }
    }

    @discardableResult
    static func write(_ fd: Int32, _ text: String) -> Bool {
        write(fd, Data(text.utf8))
    }
}

/// Reads CRLF-terminated lines (and raw header blocks) from a socket.
struct LineReader {
    let fd: Int32
    private var buffer = Data()

    init(fd: Int32) {
        self.fd = fd
    }

    mutating func readLine(timeout: Int32 = 30) -> String? {
        while true {
            if let range = buffer.firstRange(of: Data("\r\n".utf8)) {
                let line = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return line
            }
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, timeout * 1_000) > 0 else { return nil }
            var chunk = [UInt8](repeating: 0, count: 4_096)
            let count = recv(fd, &chunk, chunk.count, 0)
            guard count > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}

/// Serves a folder over FTP to one user: login, SYST, FEAT, PWD, CWD, SIZE,
/// MDTM, MLST, PASV/EPSV, REST, RETR, MLSD, LIST, NLST. Read-only.
final class TestFTPServer: @unchecked Sendable {
    let root: URL
    let user: String
    let password: String
    private(set) var port: UInt16 = 0
    private let listener: Int32
    private let lock = NSLock()
    private var stopped = false
    private var commands: [String] = []

    init?(root: URL, user: String, password: String) {
        guard let listening = TestSocket.listen() else { return nil }
        self.root = root.standardizedFileURL
        self.user = user
        self.password = password
        self.listener = listening.fd
        self.port = listening.port
        Thread.detachNewThread { [self] in
            acceptLoop()
        }
    }

    var url: URL { URL(string: "ftp://127.0.0.1:\(port)/")! }

    /// What clients sent, passwords hidden.
    var log: [String] { lock.withLock { commands } }

    func stop() {
        lock.withLock { stopped = true }
        close(listener)
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func acceptLoop() {
        while !isStopped {
            guard let client = TestSocket.accept(listener, timeout: 1) else { continue }
            Thread.detachNewThread { [self] in
                serve(client)
            }
        }
    }

    private func serve(_ control: Int32) {
        defer { close(control) }
        var reader = LineReader(fd: control)
        func reply(_ code: Int, _ text: String) {
            TestSocket.write(control, "\(code) \(text)\r\n")
        }
        reply(220, "Coreplay test FTP")
        var pendingUser: String?
        var loggedIn = false
        var directory = "/"
        var passive: Int32?
        var restart: Int64 = 0
        defer { if let passive { close(passive) } }

        while let line = reader.readLine() {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let command = parts.first?.uppercased() ?? ""
            let argument = parts.count > 1 ? parts[1] : ""
            lock.withLock { commands.append(command == "PASS" ? "PASS ****" : line) }
            switch command {
            case "USER":
                pendingUser = argument
                reply(331, "Password required")
                continue
            case "PASS":
                if pendingUser == user, argument == password {
                    loggedIn = true
                    reply(230, "Logged in")
                } else {
                    reply(530, "Login incorrect")
                }
                continue
            case "QUIT":
                reply(221, "Bye")
                return
            default:
                break
            }
            guard loggedIn else {
                reply(530, "Please log in with USER and PASS")
                continue
            }
            switch command {
            case "SYST":
                reply(215, "UNIX Type: L8")
            case "FEAT":
                TestSocket.write(control, "211-Features:\r\n MLST type*;size*;modify*;\r\n SIZE\r\n MDTM\r\n REST STREAM\r\n EPSV\r\n PASV\r\n UTF8\r\n211 End\r\n")
            case "OPTS", "TYPE", "MODE", "STRU", "NOOP", "CLNT":
                reply(200, "OK")
            case "PWD", "XPWD":
                reply(257, "\"\(directory)\" is the current directory")
            case "CWD":
                let path = resolve(argument, in: directory)
                if isDirectory(path) {
                    directory = path
                    reply(250, "OK")
                } else {
                    reply(550, "No such folder")
                }
            case "CDUP":
                directory = (directory as NSString).deletingLastPathComponent
                if directory.isEmpty { directory = "/" }
                reply(250, "OK")
            case "SIZE":
                let path = resolve(argument, in: directory)
                if let size = fileSize(path) {
                    reply(213, "\(size)")
                } else {
                    reply(550, "No such file")
                }
            case "MDTM":
                reply(213, "20260101120000")
            case "MLST":
                let path = resolve(argument, in: directory)
                guard let facts = facts(for: path) else {
                    reply(550, "No such file")
                    continue
                }
                TestSocket.write(control, "250-Listing\r\n \(facts) \(path)\r\n250 End\r\n")
            case "PASV", "EPSV":
                if let old = passive { close(old) }
                guard let listening = TestSocket.listen() else {
                    reply(425, "Can't open data connection")
                    continue
                }
                let dataPort = listening.port
                passive = listening.fd
                if command == "PASV" {
                    reply(227, "Entering Passive Mode (127,0,0,1,\(dataPort >> 8),\(dataPort & 0xFF))")
                } else {
                    reply(229, "Entering Extended Passive Mode (|||\(dataPort)|)")
                }
            case "REST":
                restart = Int64(argument) ?? 0
                reply(350, "Restarting at \(restart)")
            case "RETR":
                let path = resolve(argument, in: directory)
                guard let data = try? Data(contentsOf: fileURL(path)), !isDirectory(path) else {
                    reply(550, "No such file")
                    continue
                }
                guard let listener = passive, let connection = TestSocket.accept(listener) else {
                    reply(425, "Use PASV or EPSV first")
                    continue
                }
                close(listener)
                passive = nil
                reply(150, "Sending \(argument)")
                let start = Int(min(max(0, restart), Int64(data.count)))
                restart = 0
                let complete = TestSocket.write(connection, data.subdata(in: start..<data.count))
                close(connection)
                reply(complete ? 226 : 426, complete ? "Transfer complete" : "Transfer aborted")
            case "MLSD", "LIST", "NLST":
                let path = argument.hasPrefix("-") || argument.isEmpty ? directory : resolve(argument, in: directory)
                guard isDirectory(path) else {
                    reply(550, "No such folder")
                    continue
                }
                guard let listener = passive, let connection = TestSocket.accept(listener) else {
                    reply(425, "Use PASV or EPSV first")
                    continue
                }
                close(listener)
                passive = nil
                reply(150, "Listing")
                let names = ((try? FileManager.default.contentsOfDirectory(atPath: fileURL(path).path)) ?? []).sorted()
                var listing = ""
                for name in names {
                    let child = (path as NSString).appendingPathComponent(name)
                    switch command {
                    case "MLSD":
                        listing += "\(facts(for: child) ?? "type=file;") \(name)\r\n"
                    case "LIST":
                        let kind = isDirectory(child) ? "d" : "-"
                        listing += "\(kind)rw-r--r-- 1 owner group \(fileSize(child) ?? 0) Jan 01 12:00 \(name)\r\n"
                    default:
                        listing += "\(name)\r\n"
                    }
                }
                TestSocket.write(connection, listing)
                close(connection)
                reply(226, "Listing complete")
            case "ABOR":
                reply(226, "Aborted")
            default:
                reply(502, "\(command) not implemented")
            }
        }
    }

    private func resolve(_ argument: String, in directory: String) -> String {
        let path = argument.hasPrefix("/") ? argument : (directory as NSString).appendingPathComponent(argument)
        let standardized = (path as NSString).standardizingPath
        return standardized.isEmpty ? "/" : standardized
    }

    private func fileURL(_ path: String) -> URL {
        root.appending(path: String(path.drop { $0 == "/" }))
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: fileURL(path).path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func fileSize(_ path: String) -> Int64? {
        guard !isDirectory(path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL(path).path) else { return nil }
        return (attributes[.size] as? NSNumber)?.int64Value
    }

    private func facts(for path: String) -> String? {
        if isDirectory(path) {
            return "type=dir;modify=20260101120000;"
        }
        guard let size = fileSize(path) else { return nil }
        return "type=file;size=\(size);modify=20260101120000;"
    }
}

/// Serves a folder over HTTP/1.1 with byte ranges and keep-alive.
final class TestHTTPServer: @unchecked Sendable {
    let root: URL
    private(set) var port: UInt16 = 0
    private let listener: Int32
    private let lock = NSLock()
    private var stopped = false
    private var requests: [String] = []

    init?(root: URL) {
        guard let listening = TestSocket.listen() else { return nil }
        self.root = root.standardizedFileURL
        self.listener = listening.fd
        self.port = listening.port
        Thread.detachNewThread { [self] in
            acceptLoop()
        }
    }

    func url(for name: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)/\(name)")!
    }

    var log: [String] { lock.withLock { requests } }

    func stop() {
        lock.withLock { stopped = true }
        close(listener)
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func acceptLoop() {
        while !isStopped {
            guard let client = TestSocket.accept(listener, timeout: 1) else { continue }
            Thread.detachNewThread { [self] in
                serve(client)
            }
        }
    }

    private func serve(_ connection: Int32) {
        defer { close(connection) }
        var reader = LineReader(fd: connection)
        while let requestLine = reader.readLine(timeout: 15), !requestLine.isEmpty {
            var headers: [String: String] = [:]
            while let line = reader.readLine(), !line.isEmpty {
                if let colon = line.firstIndex(of: ":") {
                    headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
            }
            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2 else { return }
            let method = String(parts[0])
            let path = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            lock.withLock { requests.append("\(method) \(path) \(headers["range"] ?? "")") }
            let file = root.appending(path: String(path.drop { $0 == "/" }))
            guard let data = try? Data(contentsOf: file) else {
                TestSocket.write(connection, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
                continue
            }
            var start = 0
            var end = data.count - 1
            var partial = false
            if let range = headers["range"], range.hasPrefix("bytes=") {
                let bounds = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
                if bounds.count == 2 {
                    if let first = Int(bounds[0]) {
                        start = first
                        if let last = Int(bounds[1]) { end = min(last, data.count - 1) }
                    } else if let suffix = Int(bounds[1]) {
                        start = max(0, data.count - suffix)
                    }
                    partial = true
                }
            }
            guard start <= end else {
                TestSocket.write(connection, "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(data.count)\r\nContent-Length: 0\r\n\r\n")
                continue
            }
            var head = partial ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n"
            head += "Content-Type: \(Self.contentType(for: file.pathExtension))\r\n"
            head += "Content-Length: \(end - start + 1)\r\n"
            head += "Accept-Ranges: bytes\r\n"
            if partial {
                head += "Content-Range: bytes \(start)-\(end)/\(data.count)\r\n"
            }
            head += "Connection: keep-alive\r\n\r\n"
            guard TestSocket.write(connection, head) else { return }
            if method != "HEAD", !TestSocket.write(connection, data.subdata(in: start..<(end + 1))) {
                return
            }
        }
    }

    static func contentType(for ext: String) -> String {
        switch ext.lowercased() {
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        case "webm": "video/webm"
        case "mkv": "video/x-matroska"
        case "ts": "video/mp2t"
        case "m3u8": "application/vnd.apple.mpegurl"
        case "mp3": "audio/mpeg"
        case "flac": "audio/flac"
        default: "application/octet-stream"
        }
    }
}
#endif
