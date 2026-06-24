import Foundation

enum Duration {
    static func hmString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let totalMinutes = Int((Double(clamped) / 60.0).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%d:%02d", hours, minutes)
    }
}
