import Foundation
import Security

/// Where the API token lives. The app uses the Keychain; tests use `MemoryTokenStore`.
public protocol TokenStore: Sendable {
    func read() -> String?
    /// `nil` or an empty string removes the token.
    func write(_ token: String?) throws
}

public struct KeychainError: Error, Equatable, Sendable {
    public let status: OSStatus
}

/// The token as a generic password item. Never logged, never written anywhere else.
public struct KeychainTokenStore: TokenStore {
    public let service: String
    public let account: String

    public init(service: String = "uptime.api-token", account: String = "default") {
        self.service = service
        self.account = account
    }

    private func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ token: String?) throws {
        let deleted = SecItemDelete(query() as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else { throw KeychainError(status: deleted) }
        guard let token, !token.isEmpty else { return }
        var q = query()
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let added = SecItemAdd(q as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }
}

/// In-memory store for tests and previews.
public final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(_ token: String? = nil) { self.token = token }

    public func read() -> String? { lock.withLock { token } }

    public func write(_ token: String?) throws {
        lock.withLock { self.token = (token?.isEmpty ?? true) ? nil : token }
    }
}
