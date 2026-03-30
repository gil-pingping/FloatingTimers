import Foundation

enum TimerState: String, CaseIterable, Codable {
    case idle
    case running
    case paused
    case finished

    var label: String {
        switch self {
        case .idle:
            return "대기"
        case .running:
            return "진행 중"
        case .paused:
            return "일시정지"
        case .finished:
            return "완료"
        }
    }
}

struct TimerItem: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let configuredDurationText: String
    let createdAt: Date
    let initialDuration: TimeInterval
    var remainingDuration: TimeInterval
    var state: TimerState
    var endDate: Date?

    var remainingWholeSeconds: Int {
        max(Int(ceil(remainingDuration)), 0)
    }

    var remainingDurationText: String {
        DurationFormatter.clockString(totalSeconds: remainingWholeSeconds)
    }

    var progress: Double {
        guard initialDuration > 0 else {
            return 1
        }

        return min(max((initialDuration - remainingDuration) / initialDuration, 0), 1)
    }

    var isFinished: Bool {
        state == .finished
    }
}
