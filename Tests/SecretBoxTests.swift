import XCTest
@testable import SimpleChat

final class SecretBoxTests: XCTestCase {

    /// 未签名的模拟器构建里 SecItem 会因缺 keychain-access-groups 而失败（errSecMissingEntitlement）。
    /// 真机签名版没有此限制。CI 用 XCTSkip 跳过，避免误报红。
    private func requireKeychain() throws {
        do {
            _ = try KeychainSecretBox.encrypt("probe")
        } catch {
            throw XCTSkip("Keychain 在未签名模拟器构建下不可用：\(error)")
        }
    }

    func testEncryptDecryptRoundtrip() throws {
        try requireKeychain()
        let secret = "sk-1234-秘钥-🔑"
        let encrypted = try KeychainSecretBox.encrypt(secret)
        XCTAssertNotEqual(encrypted, secret)
        XCTAssertFalse(encrypted.contains("sk-1234"))
        XCTAssertEqual(try KeychainSecretBox.decrypt(encrypted), secret)
    }

    func testTwoEncryptionsDiffer() throws {
        try requireKeychain()
        // AES-GCM 随机 nonce，同一明文两次密文必然不同
        let a = try KeychainSecretBox.encrypt("same")
        let b = try KeychainSecretBox.encrypt("same")
        XCTAssertNotEqual(a, b)
    }

    func testDecryptGarbageThrows() {
        XCTAssertThrowsError(try KeychainSecretBox.decrypt("not-base64!!"))
    }

    func testWipeThenDecryptFails() throws {
        try requireKeychain()
        let encrypted = try KeychainSecretBox.encrypt("temp")
        KeychainSecretBox.wipe()
        XCTAssertThrowsError(try KeychainSecretBox.decrypt(encrypted))
        // 顺手恢复一把新钥匙，避免影响其他测试
        _ = try KeychainSecretBox.encrypt("reseed")
    }
}
