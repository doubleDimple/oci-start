import Foundation
import Security

enum RSAHelper {

    static func encrypt(plainText: String, publicKeyBase64: String) -> String? {
        let cleaned = publicKeyBase64
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard let derData = Data(base64Encoded: cleaned) else { return nil }

        // Strip PKCS#8 SubjectPublicKeyInfo header → PKCS#1 RSAPublicKey
        let keyData = stripPKCS8Header(from: derData) ?? derData

        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, &error) else {
            return nil
        }

        guard let plainData = plainText.data(using: .utf8) else { return nil }
        var encError: Unmanaged<CFError>?
        guard let cipherData = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, plainData as CFData, &encError) else {
            return nil
        }
        return (cipherData as Data).base64EncodedString()
    }

    // Strip PKCS#8 SubjectPublicKeyInfo wrapper to extract raw PKCS#1 RSAPublicKey bytes.
    // Structure: SEQUENCE { SEQUENCE { OID, NULL }, BIT STRING { RSAPublicKey } }
    private static func stripPKCS8Header(from data: Data) -> Data? {
        var bytes = [UInt8](data)
        var i = 0

        func readByte() -> UInt8? {
            guard i < bytes.count else { return nil }
            defer { i += 1 }
            return bytes[i]
        }

        func readLength() -> Int? {
            guard let first = readByte() else { return nil }
            if first & 0x80 == 0 { return Int(first) }
            let numBytes = Int(first & 0x7F)
            var len = 0
            for _ in 0..<numBytes {
                guard let b = readByte() else { return nil }
                len = (len << 8) | Int(b)
            }
            return len
        }

        // Outer SEQUENCE
        guard readByte() == 0x30, readLength() != nil else { return nil }
        // AlgorithmIdentifier SEQUENCE
        guard readByte() == 0x30, let algoLen = readLength() else { return nil }
        i += algoLen  // skip algorithm identifier content
        // BIT STRING
        guard readByte() == 0x03, readLength() != nil else { return nil }
        // Unused bits byte (should be 0x00)
        guard readByte() != nil else { return nil }

        guard i < bytes.count else { return nil }
        return Data(bytes[i...])
    }
}
