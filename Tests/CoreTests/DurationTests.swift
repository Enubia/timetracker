import XCTest
@testable import TimeTracker

final class DurationTests: XCTestCase {
    func testFormatsWholeHours() {
        XCTAssertEqual(Duration.hmString(seconds: 8 * 3600), "8:00")
    }
    func testFormatsHoursAndMinutes() {
        XCTAssertEqual(Duration.hmString(seconds: 8 * 3600 + 30 * 60), "8:30")
    }
    func testFormatsHalfHour() {
        XCTAssertEqual(Duration.hmString(seconds: 30 * 60), "0:30")
    }
    func testRoundsToNearestMinute() {
        XCTAssertEqual(Duration.hmString(seconds: 7 * 3600 + 59 * 60 + 40), "8:00")
        XCTAssertEqual(Duration.hmString(seconds: 7 * 3600 + 59 * 60 + 20), "7:59")
    }
    func testRoundingCarriesIntoHour() {
        XCTAssertEqual(Duration.hmString(seconds: 59 * 60 + 50), "1:00")
    }
    func testNegativeClampsToZero() {
        XCTAssertEqual(Duration.hmString(seconds: -100), "0:00")
    }
}
