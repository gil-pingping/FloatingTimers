import Foundation

enum DurationFormatter {
    static func clockString(totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func koreanLabel(totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        var parts: [String] = []

        if hours > 0 {
            parts.append("\(hours)시간")
        }

        if minutes > 0 {
            parts.append("\(minutes)분")
        }

        if seconds > 0 || parts.isEmpty {
            parts.append("\(seconds)초")
        }

        return parts.joined(separator: " ")
    }
}
