import XCTest
@testable import SimpleChat

final class SecretBoxTests: XCTestCase {

    func testEncryptDecryptRoundtrip() throws {
        let secret = "sk-1234-秘钥-🔑"
        let encrypted = try KeychainSecretBox.encrypt(secret)
        XCTAssertNotEqual(encrypted, secret)
        XCTAssertFalse(encrypted.contains("sk-1234"))
        XCTAssertEqual(try KeychainSecretBox.decrypt(encrypted), secret)
    }

    func testTwoEncryptionsDiffer() throws {
        // AES-GCM 随机 nonce，同一明文两次密文必然不同
        let a = try KeychainSecretBox.encrypt("same")
        let b = try KeychainSecretBox.encrypt("same")
        XCTAssertNotEqual(a, b)
    }

    func testDecryptGarbageThrows() {
        XCTAssertThrowsError(try KeychainSecretBox.decrypt("not-base64!!"))
    }

    func testWipeThenDecryptFails() throws {
        let encrypted = try KeychainSecretBox.encrypt("temp")
        KeychainSecretBox.wipe()
        XCTAssertThrowsError(try KeychainSecretBox.decrypt(encrypted))
        // 顺手恢复一把新钥匙，避免影响其他测试
        _ = try KeychainSecretBox.encrypt("reseed")
    }
}
