import Foundation
import Security

enum JWTSigner {
    enum JWTError: Error { case badPrivateKey, signFailed }

    static func assertion(for account: ServiceAccount, scope: String, now: Date, lifetimeSeconds: Int = 3600) throws -> String {
        let header = #"{"alg":"RS256","typ":"JWT"}"#
        let iat = Int(now.timeIntervalSince1970)
        let exp = iat + lifetimeSeconds
        let claims = "{\"iss\":\"\(account.clientEmail)\",\"scope\":\"\(scope)\",\"aud\":\"\(account.tokenUri)\",\"iat\":\(iat),\"exp\":\(exp)}"

        let signingInput = base64url(Data(header.utf8)) + "." + base64url(Data(claims.utf8))
        let key = try privateKey(from: account.privateKey)

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            &error
        ) as Data? else {
            throw JWTError.signFailed
        }
        return signingInput + "." + base64url(signature)
    }

    private static func privateKey(from pem: String) throws -> SecKey {
        let cleaned = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\\n", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let der = Data(base64Encoded: cleaned) else { throw JWTError.badPrivateKey }
        let pkcs1 = try stripPKCS8Header(der)
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &error) else {
            throw JWTError.badPrivateKey
        }
        return key
    }

    private static func stripPKCS8Header(_ der: Data) throws -> Data {
        let bytes = [UInt8](der)
        guard bytes.first == 0x30 else { throw JWTError.badPrivateKey }
        let marker: [UInt8] = [0x04, 0x82]
        var i = 0
        while i < bytes.count - 4 {
            if bytes[i] == marker[0] && bytes[i + 1] == marker[1] {
                let len = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
                let start = i + 4
                let end = start + len
                if end <= bytes.count {
                    return Data(bytes[start..<end])
                }
            }
            i += 1
        }
        throw JWTError.badPrivateKey
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
