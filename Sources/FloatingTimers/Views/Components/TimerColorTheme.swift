import SwiftUI

struct TimerColorTheme {
    let state: TimerState
    let hasAlert: Bool
    let isPulsing: Bool
    
    var centerColor: Color {
        switch state {
        case .running:
            return FTColors.runningCenter.opacity(0.94)
        case .paused:
            return FTColors.pausedCenter.opacity(0.94)
        case .idle:
            return FTColors.idleCenter.opacity(0.94)
        case .finished:
            return FTColors.finishedCenter.opacity(0.96)
        }
    }
    
    var edgeColor: Color {
        switch state {
        case .idle:
            return FTColors.idleEdge.opacity(0.96)
        case .running:
            return FTColors.runningEdge.opacity(0.96)
        case .paused:
            return FTColors.pausedEdge.opacity(0.96)
        case .finished:
            return FTColors.finishedEdge.opacity(0.99)
        }
    }
    
    var ringColor: Color {
        switch state {
        case .idle:
            return FTColors.idleRing
        case .running:
            return FTColors.runningRing.opacity(0.96)
        case .paused:
            return FTColors.pausedRing.opacity(0.95)
        case .finished:
            return FTColors.finishedRing.opacity(0.98)
        }
    }
    
    var haloColor: Color {
        if state == .finished {
            return Color.red.opacity(isPulsing ? 0.58 : 0.22)
        }
        
        if hasAlert {
            return Color.red.opacity(isPulsing ? 0.18 : 0.08)
        }
        
        switch state {
        case .running:
            return Color.black.opacity(0.14)
        case .paused:
            return Color.yellow.opacity(0.08)
        case .idle:
            return Color.black.opacity(0.10)
        case .finished:
            return Color.red.opacity(0.22)
        }
    }
}
