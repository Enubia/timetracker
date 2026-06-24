import Foundation

struct SessionSummary: Codable, Equatable {
    let date: String
    let total: String
    let start: String
    let breakStr: String
    let end: String

    func row() -> [String] {
        [date, total, start, breakStr, end]
    }
}
