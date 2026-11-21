import Foundation
import CryptoKit
import Security

/// iOS 版 SecretBox：主密钥存 Keychain，数据用 AES-256-GCM 加密。
/// 对应 Android 端 data/SecretBox.kt（Android Keystore + AES-256-GCM）的等价实现。
enum KeychainSecretBox {
    enum KeychainError: Error {
        case unexpected(OSStatus)
        case malformed
    }

    private static let service = "com.simplechat.ios.secretbox"
    private static let account = "master-aes-key"

    static func encrypt(_ plaintext: String) throws -> String {
        let key = try loadOrCreateKey()
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = box.combined else { throw KeychainError.malformed }
        return combined.base64EncodedString()
    }

    static func decrypt(_ base64: String) throws -> String {
        guard let data = Data(base64Encoded: base64) else { throw KeychainError.malformed }
        let key = try loadOrCreateKey()
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: key)
        return String(decoding: plain, as: UTF8.self)
    }

    static func wipe() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// 取 Keychain 里的 256 位主密钥；没有则生成并写入。
    private static func loadOrCreateKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw KeychainError.unexpected(status) }

        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        var add = query
        add[kSecValueData as String] = raw
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unexpected(addStatus) }
        return key
    }
}
