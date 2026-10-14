import Foundation
import Observation
import PlaybackCore
internal import VLCKit

/// Logins and questions VLC asks while it opens a share or a stream (its
/// dialog provider). The app shows them as a sheet; the answers go back to
/// VLC from here. Nothing about VLCKit leaves this file.
@MainActor
@Observable
public final class NetworkLoginPrompt {
    public static let shared = NetworkLoginPrompt()

    /// VLC asking for a user name and password.
    public struct Request: Identifiable, Sendable {
        public let id = UUID()
        public let title: String
        public let message: String
        public let defaultUser: String?
        /// The share or stream being opened, when known.
        public let address: URL?
    }

    /// VLC asking something with buttons, such as whether to trust a
    /// server's certificate.
    public struct Question: Identifiable, Sendable {
        public let id = UUID()
        public let title: String
        public let message: String
        public let isWarning: Bool
        /// One or two choices besides Cancel.
        public let actions: [String]
        public let cancelTitle: String
    }

    /// The login being asked for, if any (one at a time; others wait).
    public private(set) var request: Request?
    public private(set) var question: Question?
    /// VLC's last error, with when it came: the browser explains a failed
    /// folder with it ("SMB authentication failed").
    public private(set) var lastError: (message: String, date: Date)?

    /// Keeps a login the person asked to remember (the app stores it in the Keychain).
    @ObservationIgnored public var onRemember: (@MainActor (URL, NetworkCredential) -> Void)?
    /// Answers logins without asking (tests). Returning `nil` asks as usual.
    @ObservationIgnored public var automaticAnswer: (@MainActor (Request) -> NetworkCredential?)?
    /// What's being opened now, so a remembered login is filed under the
    /// right server. The browser and the player set it.
    @ObservationIgnored public var currentAddress: URL?

    @ObservationIgnored private var bridges: [ObjectIdentifier: DialogBridge] = [:]
    @ObservationIgnored private var pendingLogins: [(Request, DialogHandle)] = []
    @ObservationIgnored private var currentLogin: DialogHandle?
    @ObservationIgnored private var currentQuestion: DialogHandle?

    private init() {}

    /// Sends a libVLC instance's logins and questions here.
    func attach(to library: VLCLibrary) {
        let key = ObjectIdentifier(library)
        guard bridges[key] == nil, let bridge = DialogBridge(library: library) else { return }
        bridges[key] = bridge
    }

    // MARK: Answers

    /// Logs in. `remember` keeps the login (in the Keychain) for next time.
    public func submit(user: String, password: String, remember: Bool) {
        guard let request, let handle = currentLogin else { return }
        handle.provider.postUsername(user, andPassword: password, forDialogReference: handle.reference, store: false)
        if remember, let address = request.address {
            onRemember?(address, NetworkCredential(user: user, password: password))
        }
        finishLogin()
    }

    public func cancelLogin() {
        guard let handle = currentLogin else { return }
        handle.provider.dismissDialog(withReference: handle.reference)
        finishLogin()
    }

    /// Answers a question with one of its actions (0 or 1), or `nil` to cancel.
    public func answer(action index: Int?) {
        guard let handle = currentQuestion else { return }
        if let index {
            handle.provider.postAction(Int32(index + 1), forDialogReference: handle.reference)
        } else {
            handle.provider.dismissDialog(withReference: handle.reference)
        }
        currentQuestion = nil
        question = nil
    }

    /// VLC's newest error, if it came after `date`.
    public func error(since date: Date) -> String? {
        guard let lastError, lastError.date >= date else { return nil }
        return lastError.message
    }

    // MARK: From VLC

    fileprivate func enqueueLogin(title: String, message: String, defaultUser: String?, handle: DialogHandle) {
        let request = Request(title: title, message: message, defaultUser: defaultUser?.isEmpty == false ? defaultUser : nil, address: currentAddress)
        if let credential = automaticAnswer?(request) {
            handle.provider.postUsername(credential.user, andPassword: credential.password, forDialogReference: handle.reference, store: false)
            return
        }
        pendingLogins.append((request, handle))
        showNextLogin()
    }

    fileprivate func ask(_ question: Question, handle: DialogHandle) {
        if let current = currentQuestion {
            // One question at a time: an older one is withdrawn.
            current.provider.dismissDialog(withReference: current.reference)
        }
        currentQuestion = handle
        self.question = question
    }

    fileprivate func noteError(title: String, message: String) {
        let text = message.isEmpty ? title : message
        lastError = (text, Date.now)
    }

    /// VLC withdrew a dialog (the item stopped, or it timed out).
    fileprivate func withdraw(_ reference: NSValue) {
        if currentLogin?.reference == reference {
            finishLogin()
        } else if currentQuestion?.reference == reference {
            currentQuestion = nil
            question = nil
        } else {
            pendingLogins.removeAll { $0.1.reference == reference }
        }
    }

    private func showNextLogin() {
        guard currentLogin == nil, !pendingLogins.isEmpty else { return }
        let (next, handle) = pendingLogins.removeFirst()
        currentLogin = handle
        request = next
    }

    private func finishLogin() {
        currentLogin = nil
        request = nil
        showNextLogin()
    }
}

/// A dialog VLC is waiting on, and the provider to answer it through.
private struct DialogHandle: @unchecked Sendable {
    let provider: VLCDialogProvider
    let reference: NSValue
}

/// Receives one libVLC instance's dialogs on VLC's threads and passes them
/// to `NetworkLoginPrompt` on the main actor.
private final class DialogBridge: NSObject, VLCCustomDialogRendererProtocol, @unchecked Sendable {
    let provider: VLCDialogProvider

    init?(library: VLCLibrary) {
        guard let provider = VLCDialogProvider(library: library, customUI: true) else { return nil }
        self.provider = provider
        super.init()
        provider.customRenderer = self
    }

    func showError(withTitle error: String, message: String) {
        Task { @MainActor in
            NetworkLoginPrompt.shared.noteError(title: error, message: message)
        }
    }

    func showLogin(withTitle title: String, message: String, defaultUsername username: String?, askingForStorage: Bool, withReference reference: NSValue) {
        let handle = DialogHandle(provider: provider, reference: reference)
        Task { @MainActor in
            NetworkLoginPrompt.shared.enqueueLogin(title: title, message: message, defaultUser: username, handle: handle)
        }
    }

    func showQuestion(withTitle title: String, message: String, type questionType: VLCDialogQuestionType, cancel cancelString: String?, action1String: String?, action2String: String?, withReference reference: NSValue) {
        let handle = DialogHandle(provider: provider, reference: reference)
        let question = NetworkLoginPrompt.Question(
            title: title,
            message: message,
            isWarning: questionType != .normal,
            actions: [action1String, action2String].compactMap { $0?.isEmpty == false ? $0 : nil },
            cancelTitle: cancelString?.isEmpty == false ? cancelString! : "Cancel"
        )
        Task { @MainActor in
            NetworkLoginPrompt.shared.ask(question, handle: handle)
        }
    }

    // Progress dialogs (VLC's "Buffering…" and similar) aren't shown: the
    // player has its own spinner.
    func showProgress(withTitle title: String, message: String, isIndeterminate: Bool, position: Float, cancel cancelString: String?, withReference reference: NSValue) {}

    func updateProgress(withReference reference: NSValue, message: String?, position: Float) {}

    func cancelDialog(withReference reference: NSValue) {
        let box = DialogHandle(provider: provider, reference: reference)
        Task { @MainActor in
            NetworkLoginPrompt.shared.withdraw(box.reference)
        }
    }
}
