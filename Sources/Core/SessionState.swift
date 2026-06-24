import Foundation

enum SessionState: String, Codable {
    case idle
    case working
    case onBreak
    case ended
}

enum SessionError: Error, Equatable {
    case invalidTransition
}
