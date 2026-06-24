import XCTest
@testable import TimeTracker

final class AutoBreakTests: XCTestCase {
    private let tz = TimeZone(identifier: "Europe/Vienna")!
    private func d(_ hms: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = tz
        return f.date(from: "2026-06-24T\(hms)+02:00")!
    }
    private func ended(start: String, end: String, breakSecs: Int) -> WorkSession {
        var s = WorkSession.idle()
        try! s.start(at: d(start))
        s.completedBreakSeconds = breakSecs
        try! s.end(at: d(end))
        return s
    }

    func testAutoBreakFiresWhenZeroBreakAndOverSixHours() {
        XCTAssertEqual(AutoBreak.effectiveBreakSeconds(grossSeconds: 7 * 3600, manualBreakSeconds: 0), 30 * 60)
    }
    func testAutoBreakAtExactlySixHours() {
        XCTAssertEqual(AutoBreak.effectiveBreakSeconds(grossSeconds: 6 * 3600, manualBreakSeconds: 0), 30 * 60)
    }
    func testNoAutoBreakJustUnderSixHours() {
        XCTAssertEqual(AutoBreak.effectiveBreakSeconds(grossSeconds: 6 * 3600 - 60, manualBreakSeconds: 0), 0)
    }
    func testNoAutoBreakWhenAnyManualBreak() {
        XCTAssertEqual(AutoBreak.effectiveBreakSeconds(grossSeconds: 10 * 3600, manualBreakSeconds: 5 * 60), 5 * 60)
    }

    func testSummaryNoBreakOverSixHoursGetsAutoBreak() {
        let s = ended(start: "09:00:00", end: "16:00:00", breakSecs: 0) // 7h gross
        let sum = AutoBreak.summarize(s, timeZone: tz)
        XCTAssertEqual(sum.date, "2026-06-24")
        XCTAssertEqual(sum.start, "09:00")
        XCTAssertEqual(sum.end, "16:00")
        XCTAssertEqual(sum.breakStr, "0:30")
        XCTAssertEqual(sum.total, "6:30")
        XCTAssertEqual(sum.row(), ["2026-06-24", "6:30", "09:00", "0:30", "16:00"])
    }

    func testSummaryWithManualBreak() {
        let s = ended(start: "09:00:00", end: "18:00:00", breakSecs: 60 * 60) // 9h gross, 1h break
        let sum = AutoBreak.summarize(s, timeZone: tz)
        XCTAssertEqual(sum.breakStr, "1:00")
        XCTAssertEqual(sum.total, "8:00")
    }

    func testSummaryShortDayNoAutoBreak() {
        let s = ended(start: "09:00:00", end: "14:00:00", breakSecs: 0) // 5h gross
        let sum = AutoBreak.summarize(s, timeZone: tz)
        XCTAssertEqual(sum.breakStr, "0:00")
        XCTAssertEqual(sum.total, "5:00")
    }
}
