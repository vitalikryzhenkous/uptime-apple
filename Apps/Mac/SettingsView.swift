import SwiftUI
import UptimeKit

struct SettingsView: View {
    @Environment(LiveStore.self) private var store
    @Environment(AssetStore.self) private var assets
    @Environment(\.colorScheme) private var scheme
    let refreshAssets: @MainActor () -> Void
    @State private var address = Prefs.baseURL.absoluteString
    @State private var token = ""
    @State private var hasToken = Prefs.tokens.read() != nil
    @State private var lang = Prefs.lang ?? ""
    @State private var problem: String?

    var body: some View {
        let s = assets.strings
        Form {
            Section {
                TextField(s.tr("app.set.server", fallback: "Server"), text: $address,
                          prompt: Text(ServerConfig.defaultBaseURL.absoluteString))
                SecureField(s.tr("app.set.token", fallback: "Token"), text: $token,
                            prompt: Text(hasToken ? s.tr("app.set.token_saved", fallback: "saved in Keychain — type to replace")
                                                  : "UPTIME_API_TOKEN"))
            } footer: {
                Text(s.tr("app.set.token_help", fallback: "The token is the UPTIME_API_TOKEN line in ~/apps/uptime-board/.env "
                          + "on the M920q. It is kept only in your Keychain."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(s.tr("app.set.lang", fallback: "Language"), selection: $lang) {
                    Text(defaultLangLabel(s)).tag("")
                    ForEach(assets.ext?.langs ?? []) { l in
                        Text(l.name).tag(l.code)
                    }
                }
                .onChange(of: lang) { _, new in
                    Prefs.lang = new.isEmpty ? nil : new
                    refreshAssets()
                }
            } footer: {
                Text(s.tr("app.set.lang_help",
                          fallback: "Texts and the cat's lines come from the board's /locales, with your ~/.uptime/ext additions."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let problem {
                Text(problem).foregroundStyle(.red).font(.callout)
            }
            ConnectionLine(connection: store.connection, lastUpdate: store.lastUpdate, strings: s, theme: Theme.of(scheme))
            if store.drops > 0 {
                // diagnostics for the frequent "-1005": how often the stream dropped since launch, and why
                Text(dropsText(s)).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if hasToken {
                    Button(s.tr("app.set.remove", fallback: "Remove token"), role: .destructive, action: removeToken)
                }
                Spacer()
                Button(s.tr("app.reconnect", fallback: "Reconnect")) { store.start() }
                Button(s.tr("app.set.save", fallback: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.vertical, 8)
    }

    private func dropsText(_ s: Strings) -> String {
        let time = store.lastErrorAt?.formatted(date: .omitted, time: .shortened) ?? "—"
        let reason = store.lastError ?? "—"
        return s.tr("app.set.drops", ["n": .number(Double(store.drops)), "reason": .string(reason), "time": .string(time)],
                    fallback: "Connection drops since launch: \(store.drops) · last: \(reason) at \(time)")
    }

    private func defaultLangLabel(_ s: Strings) -> String {
        let code = assets.ext?.defaultLang
        let name = assets.ext?.langs.first { $0.code == code }?.name ?? code ?? "—"
        return s.tr("app.set.lang_default", ["name": .string(name)], fallback: "Board default (\(name))")
    }

    private func save() {
        let s = assets.strings
        guard let url = Prefs.validURL(address) else {
            problem = s.tr("app.set.https", fallback: "The address must start with https://")
            return
        }
        do {
            Prefs.baseURL = url
            if !token.isEmpty {
                try Prefs.tokens.write(token.trimmingCharacters(in: .whitespacesAndNewlines))
                token = ""
            }
            hasToken = Prefs.tokens.read() != nil
            problem = nil
            store.start()
            refreshAssets()
        } catch {
            problem = s.tr("app.set.keychain_error", ["error": .string("\(error)")],
                           fallback: "Could not write to the Keychain (\(error))")
        }
    }

    private func removeToken() {
        let s = assets.strings
        do {
            try Prefs.tokens.write(nil)
            hasToken = false
            problem = nil
            store.start() // → "No token"
        } catch {
            problem = s.tr("app.set.keychain_error", ["error": .string("\(error)")],
                           fallback: "Could not write to the Keychain (\(error))")
        }
    }
}
