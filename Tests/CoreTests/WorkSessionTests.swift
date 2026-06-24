import XCTest
@testable import TimeTracker

final class WorkSessionTests: XCTestCase {
    private func d(_ hms: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return f.date(from: "2026-06-24T\(hms)+02:00")!
    }

    func testStartFromIdleEntersWorking() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        XCTAssertEqual(s.state, .working)
        XCTAssertEqual(s.start, d("09:00:00"))
    }

    func testCannotStartTwice() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        XCTAssertThrowsError(try s.start(at: d("09:05:00"))) {
            XCTAssertEqual($0 as? SessionError, .invalidTransition)
        }
    }

    func testBreakOnlyFromWorking() {
        var s = WorkSession.idle()
        XCTAssertThrowsError(try s.beginBreak(at: d("09:00:00")))
    }

    func testBreaksAccumulate() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        try s.beginBreak(at: d("10:00:00"))
        try s.endBreak(at: d("10:15:00"))
        try s.beginBreak(at: d("12:00:00"))
        try s.endBreak(at: d("12:30:00"))
        XCTAssertEqual(s.completedBreakSeconds, 45 * 60)
        XCTAssertEqual(s.state, .working)
    }

    func testInProgressBreakCountedAsOfNow() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        try s.beginBreak(at: d("10:00:00"))
        XCTAssertEqual(s.breakSeconds(asOf: d("10:10:00")), 10 * 60)
    }

    func testEndFromWorkingAndOnBreak() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        try s.end(at: d("17:00:00"))
        XCTAssertEqual(s.state, .ended)
        XCTAssertEqual(s.end, d("17:00:00"))

        var s2 = WorkSession.idle()
        try s2.start(at: d("09:00:00"))
        try s2.beginBreak(at: d("16:00:00"))
        try s2.end(at: d("17:00:00"))
        XCTAssertEqual(s2.state, .ended)
        XCTAssertEqual(s2.end, d("17:00:00"))
    }

    func testEndWhileOnBreakFinalizesOpenBreak() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        try s.beginBreak(at: d("12:00:00"))
        try s.end(at: d("12:30:00"))
        XCTAssertEqual(s.breakSeconds(asOf: d("12:30:00")), 30 * 60)
        XCTAssertEqual(s.completedBreakSeconds, 30 * 60)
        XCTAssertNil(s.currentBreakStart)
    }

    func testNoTransitionsFromEnded() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        try s.end(at: d("17:00:00"))
        XCTAssertThrowsError(try s.start(at: d("17:01:00"))) {
            XCTAssertEqual($0 as? SessionError, .invalidTransition)
        }
        XCTAssertThrowsError(try s.beginBreak(at: d("17:01:00"))) {
            XCTAssertEqual($0 as? SessionError, .invalidTransition)
        }
        XCTAssertThrowsError(try s.endBreak(at: d("17:01:00"))) {
            XCTAssertEqual($0 as? SessionError, .invalidTransition)
        }
        XCTAssertThrowsError(try s.end(at: d("17:01:00"))) {
            XCTAssertEqual($0 as? SessionError, .invalidTransition)
        }
    }

    func testEndBreakOnlyFromOnBreak() throws {
        var working = WorkSession.idle()
        try working.start(at: d("09:00:00"))
        XCTAssertThrowsError(try working.endBreak(at: d("09:05:00"))) {
            XCTAssertEqual($0 as? SessionError, .invalidTransition)
        }

        var idle = WorkSession.idle()
        XCTAssertThrowsError(try idle.endBreak(at: d("09:00:00"))) {
            XCTAssertEqual($0 as? SessionError, .invalidTransition)
        }
    }

    func testNetSeconds() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        try s.beginBreak(at: d("12:00:00"))
        try s.endBreak(at: d("13:00:00"))
        try s.end(at: d("18:00:00"))
        XCTAssertEqual(s.grossSeconds(asOf: d("18:00:00")), 9 * 3600)
        XCTAssertEqual(s.netSeconds(asOf: d("18:00:00")), 8 * 3600)
    }
}
