import CodexBarCore
import Foundation
import LocalAuthentication
import Security

/// Reads Claude Code's existing OAuth credential without ever presenting a
/// Keychain authentication dialog. If the item requires interaction, callers
/// can fall back to the CLI probe instead.
enum ClaudeKeychainCredentialsReader {
    static func load() throws -> ClaudeOAuthCredentials? {
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw ReadError.invalidData }
            return try ClaudeOAuthCredentials.parse(data: data)
        case errSecItemNotFound, errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return nil
        default:
            throw ReadError.keychain(status)
        }
    }
}

private enum ReadError: LocalizedError {
    case invalidData
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "Claude Keychain 项目不是可读取的数据"
        case let .keychain(status):
            (SecCopyErrorMessageString(status, nil) as String?)
                .map { "Claude Keychain 读取失败：\($0)" }
                ?? "Claude Keychain 读取失败（\(status)）"
        }
    }
}
