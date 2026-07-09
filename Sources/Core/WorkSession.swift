import Foundation

struct WorkSession: Codable, Equatable {
    var state: SessionState
    var start: Date?
    var end: Date?
    var completedBreakSeconds: Int
    var currentBreakStart: Date?

    static func idle() -> WorkSession {
        WorkSession(state: .idle, start: nil, end: nil,
                    completedBreakSeconds: 0, currentBreakStart: nil)
    }

    mutating func start(at now: Date) throws {
        guard state == .idle else { throw SessionError.invalidTransition }
        state = .working
        start = now
    }

    mutating func beginBreak(at now: Date) throws {
        guard state == .working else { throw SessionError.invalidTransition }
        state = .onBreak
        currentBreakStart = now
    }

    mutating func endBreak(at now: Date) throws {
        guard state == .onBreak, let began = currentBreakStart else {
            throw SessionError.invalidTransition
        }
        completedBreakSeconds += Int(now.timeIntervalSince(began))
        currentBreakStart = nil
        state = .working
    }

    mutating func end(at now: Date) throws {
        guard state == .working || state == .onBreak else {
            throw SessionError.invalidTransition
        }
        if state == .onBreak, let began = currentBreakStart {
            completedBreakSeconds += Int(now.timeIntervalSince(began))
            currentBreakStart = nil
        }
        end = now
        state = .ended
        clampBreakToGross(asOf: now)
    }

    mutating func setBreakSeconds(_ seconds: Int, asOf now: Date) throws {
        guard state == .working || state == .onBreak else {
            throw SessionError.invalidTransition
        }
        completedBreakSeconds = min(max(0, seconds), grossSeconds(asOf: now))
        currentBreakStart = nil
        if state == .onBreak {
            state = .working
        }
    }

    mutating func adjustStart(to newStart: Date, asOf now: Date) throws {
        guard state == .working || state == .onBreak, newStart <= now else {
            throw SessionError.invalidTransition
        }
        start = newStart
        clampBreakToGross(asOf: now)
    }

    mutating func clampBreakToGross(asOf now: Date) {
        completedBreakSeconds = max(0, completedBreakSeconds)
        let cap = grossSeconds(asOf: now)
        guard breakSeconds(asOf: now) > cap else { return }
        switch state {
        case .onBreak:
            let activeSeconds = currentBreakStart.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
            if activeSeconds <= cap {
                completedBreakSeconds = cap - activeSeconds
            } else {
                completedBreakSeconds = 0
                currentBreakStart = now.addingTimeInterval(TimeInterval(-cap))
            }
        default:
            completedBreakSeconds = cap
        }
    }

    func breakSeconds(asOf now: Date) -> Int {
        var total = completedBreakSeconds
        if state == .onBreak, let began = currentBreakStart {
            total += Int(now.timeIntervalSince(began))
        }
        return max(0, total)
    }

    func grossSeconds(asOf now: Date) -> Int {
        guard let start else { return 0 }
        let stop = end ?? now
        return max(0, Int(stop.timeIntervalSince(start)))
    }

    func netSeconds(asOf now: Date) -> Int {
        max(0, grossSeconds(asOf: now) - breakSeconds(asOf: now))
    }
}
