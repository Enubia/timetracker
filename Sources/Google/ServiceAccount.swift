import Foundation

struct ServiceAccount: Decodable {
    let clientEmail: String
    let privateKey: String
    let tokenUri: String

    enum CodingKeys: String, CodingKey {
        case clientEmail = "client_email"
        case privateKey = "private_key"
        case tokenUri = "token_uri"
    }

    static func from(_ data: Data) throws -> ServiceAccount {
        try JSONDecoder().decode(ServiceAccount.self, from: data)
    }
}
