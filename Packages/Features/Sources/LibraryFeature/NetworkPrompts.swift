import DesignSystem
import PlaybackEngine
import SwiftUI

extension View {
    /// Shows the logins and questions VLC asks while opening a share or a
    /// stream, as a card over everything (it works over the full-screen
    /// player too, where a sheet couldn't be presented).
    public func networkPrompts() -> some View {
        overlay {
            NetworkPromptOverlay()
        }
    }
}

private struct NetworkPromptOverlay: View {
    var body: some View {
        let prompt = NetworkLoginPrompt.shared
        ZStack {
            if let request = prompt.request {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {}
                LoginCard(request: request)
                    .id(request.id)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            } else if let question = prompt.question {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                QuestionCard(question: question)
                    .id(question.id)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(Motion.quick, value: prompt.request?.id)
        .animation(Motion.quick, value: prompt.question?.id)
    }
}

private struct LoginCard: View {
    let request: NetworkLoginPrompt.Request
    @State private var user = ""
    @State private var password = ""
    @State private var remember = true
    @FocusState private var focused: Field?

    private enum Field {
        case user, password
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(request.title.isEmpty ? "Log In" : request.title)
                    .font(.headline)
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.accentColor)
            }
            Text(request.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                TextField("User Name", text: $user)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .focused($focused, equals: .user)
                    .onSubmit { focused = .password }
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .onSubmit(submit)
            }
            .textFieldStyle(.roundedBorder)
            if request.address != nil {
                Toggle("Remember in Keychain", isOn: $remember)
                    .font(.subheadline)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    NetworkLoginPrompt.shared.cancelLogin()
                }
                .keyboardShortcut(.cancelAction)
                Button("Log In", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(user.isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .padding(24)
        .onAppear {
            user = request.defaultUser ?? ""
            focused = user.isEmpty ? .user : .password
        }
    }

    private func submit() {
        guard !user.isEmpty else { return }
        NetworkLoginPrompt.shared.submit(user: user, password: password, remember: remember)
    }
}

private struct QuestionCard: View {
    let question: NetworkLoginPrompt.Question

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(question.title)
                    .font(.headline)
            } icon: {
                Image(systemName: question.isWarning ? "exclamationmark.triangle.fill" : "questionmark.circle.fill")
                    .foregroundStyle(question.isWarning ? Color.orange : Color.accentColor)
            }
            Text(question.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(question.cancelTitle, role: .cancel) {
                    NetworkLoginPrompt.shared.answer(action: nil)
                }
                .keyboardShortcut(.cancelAction)
                ForEach(Array(question.actions.enumerated()), id: \.offset) { index, title in
                    Button(title) {
                        NetworkLoginPrompt.shared.answer(action: index)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .padding(24)
    }
}
