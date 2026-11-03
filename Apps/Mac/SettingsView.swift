import SwiftUI
import UptimeKit

struct SettingsView: View {
    @Environment(LiveStore.self) private var store
    @State private var address = Prefs.baseURL.absoluteString
    @State private var token = ""
    @State private var hasToken = Prefs.tokens.read() != nil
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                TextField("Server", text: $address, prompt: Text(ServerConfig.defaultBaseURL.absoluteString))
                SecureField("Token", text: $token,
                            prompt: Text(hasToken ? "saved in Keychain — type to replace" : "UPTIME_API_TOKEN"))
            } footer: {
                Text("The token is the UPTIME_API_TOKEN line in ~/apps/uptime-board/.env on the M920q. "
                     + "It is kept only in your Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let problem {
                Text(problem).foregroundStyle(.red).font(.callout)
            }
            ConnectionLine(connection: store.connection, lastUpdate: store.lastUpdate)

            HStack {
                if hasToken {
                    Button("Remove token", role: .destructive, action: removeToken)
                }
                Spacer()
                Button("Reconnect") { store.start() }
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.vertical, 8)
    }

    private func save() {
        guard let url = Prefs.validURL(address) else {
            problem = "The address must start with https://"
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
        } catch {
            problem = "Could not save to the Keychain (\(error))"
        }
    }

    private func removeToken() {
        do {
            try Prefs.tokens.write(nil)
            hasToken = false
            problem = nil
            store.start() // → "No token"
        } catch {
            problem = "Could not remove from the Keychain (\(error))"
        }
    }
}
