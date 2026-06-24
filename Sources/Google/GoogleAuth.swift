import Foundation

actor GoogleAuth {
    enum AuthError: Error { case tokenRequestFailed(Int), badResponse }

    private let account: ServiceAccount
    private let scope = "https://www.googleapis.com/auth/spreadsheets"
    private var cachedToken: String?
    private var expiresAt: Date = .distantPast

    init(account: ServiceAccount) {
        self.account = account
    }

    func accessToken(now: Date = Date()) async throws -> String {
        if let token = cachedToken, now < expiresAt.addingTimeInterval(-60) {
            return token
        }
        let assertion = try JWTSigner.assertion(for: account, scope: scope, now: now)
        var request = URLRequest(url: URL(string: account.tokenUri)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(assertion)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.badResponse }
        guard http.statusCode == 200 else { throw AuthError.tokenRequestFailed(http.statusCode) }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedToken = decoded.access_token
        expiresAt = now.addingTimeInterval(TimeInterval(decoded.expires_in))
        return decoded.access_token
    }
}
