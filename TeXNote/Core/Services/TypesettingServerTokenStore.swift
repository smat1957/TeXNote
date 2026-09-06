import Foundation
import Security

enum TypesettingServerTokenStore {
    /// P1が発行したユーザーJWTを保存するアカウント名です。
    /// P1--P2間の固定トークンはアプリへ保存しません。
    private static let account = "p1-user-access-token"

    static func load() -> String {
        deleteLegacyP2Token()
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return ""
        }
        return token
    }

    static func save(_ token: String) throws {
        deleteLegacyP2Token()
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            delete()
            return
        }

        let data = Data(normalizedToken.utf8)
        let status: OSStatus
        if load().isEmpty {
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        } else {
            status = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
        }

        guard status == errSecSuccess else {
            throw TypesettingServerTokenError.keychain(status)
        }
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
        deleteLegacyP2Token()
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static var service: String {
        "\(Bundle.main.bundleIdentifier ?? "jp.texnote.app").p1-authentication"
    }

    /// 旧P2直結版が保存した固定APIトークンをKeychainから除去します。
    private static func deleteLegacyP2Token() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "jp.texnote.app"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(bundleIdentifier).typesetting-server",
            kSecAttrAccount as String: "typesetting-api-token"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum TypesettingServerTokenError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            if let message = SecCopyErrorMessageString(status, nil) {
                return "ログイン情報を保存できませんでした: \(message)"
            }
            return "ログイン情報を保存できませんでした（\(status)）。"
        }
    }
}
