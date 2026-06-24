import Foundation

enum AutoBreak {
    static let thresholdSeconds = 6 * 3600
    static let autoBreakSeconds = 30 * 60

    static func effectiveBreakSeconds(grossSeconds: Int, manualBreakSeconds: Int) -> Int {
        if manualBreakSeconds == 0 && grossSeconds >= thresholdSeconds {
            return autoBreakSeconds
        }
        return manualBreakSeconds
    }

    static func summarize(_ session: WorkSession, timeZone: TimeZone) -> SessionSummary {
        let start = session.start!
        let end = session.end!
        let gross = max(0, Int(end.timeIntervalSince(start)))
        let manualBreak = session.breakSeconds(asOf: end)
        let effBreak = effectiveBreakSeconds(grossSeconds: gross, manualBreakSeconds: manualBreak)
        let total = max(0, gross - effBreak)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let dateFmt = DateFormatter()
        dateFmt.calendar = cal
        dateFmt.timeZone = timeZone
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.dateFormat = "yyyy-MM-dd"
        let clockFmt = DateFormatter()
        clockFmt.calendar = cal
        clockFmt.timeZone = timeZone
        clockFmt.locale = Locale(identifier: "en_US_POSIX")
        clockFmt.dateFormat = "HH:mm"

        return SessionSummary(
            date: dateFmt.string(from: start),
            total: Duration.hmString(seconds: total),
            start: clockFmt.string(from: start),
            breakStr: Duration.hmString(seconds: effBreak),
            end: clockFmt.string(from: end)
        )
    }
}
