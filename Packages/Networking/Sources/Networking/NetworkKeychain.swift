import Foundation
import PlaybackCore
#if canImport(Security)
import Security
#endif

/// Logins for shares, kept in the Keychain as internet passwords (one per
/// protocol, server, port and user), never synced and never in a file.
public enum NetworkKeychain {
    /// The login for `url`'s server: the saved one for `user` if given,
    /// otherwise the first one for that server.
    public static func credential(for url: URL, user: String? = nil) -> NetworkCredential? {
        #if canImport(Security)
        guard var query = baseQuery(for: url, user: user) else { return nil }
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8),
              let account = item[kSecAttrAccount as String] as? String else { return nil }
        let domain = item[kSecAttrSecurityDomain as String] as? String
        return NetworkCredential(user: account, password: password, domain: domain)
        #else
        return nil
        #endif
    }

    /// Saves (or replaces) the login for `url`'s server.
    @discardableResult
    public static func save(_ credential: NetworkCredential, for url: URL) -> Bool {
        #if canImport(Security)
        guard let query = baseQuery(for: url, user: credential.user) else { return false }
        var attributes: [String: Any] = [kSecValueData as String: Data(credential.password.utf8)]
        if let domain = credential.domain {
            attributes[kSecAttrSecurityDomain as String] = domain
        }
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { $1 }
            item[kSecAttrLabel as String] = "Coreplay: \(url.scheme ?? "")://\(NetworkAddress.server(of: url))"
            #if os(iOS)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #endif
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
        #else
        return false
        #endif
    }

    /// Forgets the login for `url`'s server (`user`'s, or all of them).
    public static func delete(for url: URL, user: String? = nil) {
        #if canImport(Security)
        guard let query = baseQuery(for: url, user: user) else { return }
        SecItemDelete(query as CFDictionary)
        #endif
    }

    #if canImport(Security)
    private static func baseQuery(for url: URL, user: String?) -> [String: Any]? {
        guard let networkProtocol = NetworkProtocol(scheme: url.scheme),
              let host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host.lowercased(),
            kSecAttrPort as String: url.port ?? networkProtocol.defaultPort ?? 0,
        ]
        if let keychainProtocol = keychainProtocol(networkProtocol) {
            query[kSecAttrProtocol as String] = keychainProtocol
        } else {
            query[kSecAttrComment as String] = networkProtocol.scheme
        }
        if let user, !user.isEmpty {
            query[kSecAttrAccount as String] = user
        }
        return query
    }

    private static func keychainProtocol(_ networkProtocol: NetworkProtocol) -> CFString? {
        switch networkProtocol {
        case .smb: kSecAttrProtocolSMB
        case .ftp: kSecAttrProtocolFTP
        case .sftp: kSecAttrProtocolSSH
        case .nfs, .upnp: nil
        }
    }
    #endif
}
