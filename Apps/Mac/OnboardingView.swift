import AppKit
import SwiftUI
import UptimeKit
import UserNotifications

/// The first-run wizard (opens while there is no token) and "Pair with a code…" in Settings:
/// board address → one-time code → connection check → notifications and the hotkey.
/// An `uptime://pair` link (⌘-click in Terminal) opens it with the code and address filled in.
struct OnboardingView: View {
    enum Step { case server, code, check, done }

    @Environment(LiveStore.self) private var store
    @Environment(AssetStore.self) private var assets
    let refreshAssets: @MainActor () -> Void
    let finish: @MainActor () -> Void
    @State private var step: Step
    @State private var address: String
    @State private var code: String
    @State private var busy = false
    @State private var problem: String?
    @State private var sshUser = Prefs.sshUser
    @State private var notifyAsked = false

    init(link: Pairing.Link?, refreshAssets: @escaping @MainActor () -> Void, finish: @escaping @MainActor () -> Void) {
        self.refreshAssets = refreshAssets
        self.finish = finish
        _address = State(initialValue: (link?.baseURL ?? Prefs.baseURL).absoluteString)
        _code = State(initialValue: link?.code ?? "")
        _step = State(initialValue: link == nil ? .server : .code)
    }

    var body: some View {
        let s = assets.strings
        VStack(alignment: .leading, spacing: 14) {
            Text(title(s)).font(.title2.bold())
            switch step {
            case .server: serverStep(s)
            case .code: codeStep(s)
            case .check: checkStep(s)
            case .done: doneStep(s)
            }
            if let problem {
                Text(problem).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            buttons(s)
        }
        .padding(24)
        .frame(width: 460, height: 370)
    }

    private func title(_ s: Strings) -> String {
        switch step {
        case .server: s.tr("app.onb.server.title", fallback: "Where is your board?")
        case .code: s.tr("app.onb.code.title", fallback: "Pairing code")
        case .check: s.tr("app.onb.check.title", fallback: "Connecting")
        case .done: s.tr("app.onb.done.title", fallback: "Ready")
        }
    }

    // MARK: steps

    private func serverStep(_ s: Strings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.tr("app.onb.server.text", fallback: "Uptime shows your Claude Code sessions from the board on the M920q. "
                      + "Its address over Tailscale, https only."))
                .fixedSize(horizontal: false, vertical: true)
            TextField(s.tr("app.set.server", fallback: "Server"), text: $address,
                      prompt: Text(ServerConfig.defaultBaseURL.absoluteString))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func codeStep(_ s: Strings) -> some View {
        let command = Prefs.validURL(address).map { Pairing.command(baseURL: $0, user: sshUser) } ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Text(s.tr("app.onb.code.text", fallback: "Run this in Terminal on this Mac and type here the 6 digits it prints. "
                      + "The code works once, for 2 minutes."))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) { // the account on the board's machine: ssh <user>@<board host>
                Text("ssh").font(.system(.caption, design: .monospaced))
                TextField("", text: $sshUser, prompt: Text("lenovo"))
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .onChange(of: sshUser) { _, new in Prefs.sshUser = new }
                Text("@\(Prefs.validURL(address)?.host ?? "…")").font(.system(.caption, design: .monospaced))
            }
            CopyLine(text: command, strings: s)
            TextField("123 456", text: $code)
                .font(.system(.title2, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .onSubmit(pair)
        }
    }

    private func checkStep(_ s: Strings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(s.tr("app.onb.check.text", fallback: "This Mac got its own token (in your Keychain). "
                      + "Revoke it on the M920q with tools/pair.py --revoke."))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if store.connection == .live {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(s.tr("app.onb.check.live", fallback: "Live: the board answers."))
                } else {
                    ProgressView().controlSize(.small)
                    Text(s.tr("app.onb.check.wait", fallback: "Waiting for the board…"))
                }
            }
        }
    }

    private func doneStep(_ s: Strings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(s.tr("app.onb.done.text", fallback: "Buddy lives in the menu bar: green eyes — working, yellow — waiting "
                      + "for you, red — a permission or a question. ⌥⌘U opens the card that needs you most."))
                .fixedSize(horizontal: false, vertical: true)
            Button(notifyAsked ? s.tr("app.onb.notify.asked", fallback: "Asked — see System Settings › Notifications")
                               : s.tr("app.onb.notify", fallback: "Allow notifications about permission requests")) {
                notifyAsked = true
                Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            }
            .disabled(notifyAsked)
        }
    }

    // MARK: buttons

    @ViewBuilder private func buttons(_ s: Strings) -> some View {
        HStack {
            if step == .code {
                Button(s.tr("app.onb.back", fallback: "Back")) { problem = nil; step = .server }
            }
            Spacer()
            switch step {
            case .server:
                Button(s.tr("app.onb.next", fallback: "Next"), action: checkAddress).keyboardShortcut(.defaultAction)
            case .code:
                Button(s.tr("app.onb.pair", fallback: "Pair"), action: pair)
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || Pairing.code(code) == nil)
            case .check:
                Button(s.tr("app.onb.next", fallback: "Next")) { step = .done }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.connection != .live)
            case .done:
                Button(s.tr("app.onb.finish", fallback: "Done")) { finish() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func checkAddress() {
        guard Prefs.validURL(address) != nil else {
            problem = assets.strings.tr("app.set.https", fallback: "The address must start with https://")
            return
        }
        problem = nil
        step = .code
    }

    private func pair() {
        let s = assets.strings
        guard let url = Prefs.validURL(address), let digits = Pairing.code(code), !busy else { return }
        busy = true
        problem = nil
        let name = Host.current().localizedName ?? "Mac"
        Task {
            defer { busy = false }
            do {
                switch try await Pairing.claim(code: digits, name: name, baseURL: url) {
                case .paired(let token):
                    try Prefs.tokens.write(token)
                    Prefs.baseURL = url
                    store.start()
                    refreshAssets()
                    step = .check
                case .refused("rate"):
                    problem = s.tr("app.onb.err.rate", fallback: "Too many attempts. Wait a minute and try again.")
                case .refused("old_board"):
                    problem = s.tr("app.onb.err.old", fallback: "This board can't pair yet — update uptime-board.")
                case .refused:
                    problem = s.tr("app.onb.err.code", fallback: "The code is wrong, used or expired. Print a new one.")
                }
            } catch let error as KeychainError {
                problem = s.tr("app.set.keychain_error", ["error": .string("\(error)")],
                               fallback: "Could not write to the Keychain (\(error))")
            } catch {
                problem = s.tr("app.onb.err.net", ["error": .string(error.localizedDescription)],
                               fallback: "No answer from the board (\(error.localizedDescription)). Check the address and Tailscale.")
            }
        }
    }
}
