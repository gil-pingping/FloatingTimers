import SwiftUI

enum FTColors {
    static let accentBlue = Color(red: 0.63, green: 0.90, blue: 1.0)
    static let runningRing = Color(red: 0.67, green: 0.92, blue: 1.00)
    static let pausedRing = Color(red: 0.98, green: 0.83, blue: 0.42)
    static let finishedRing = Color(red: 1.00, green: 0.26, blue: 0.22)
    static let idleRing = Color.white.opacity(0.24)
    
    static let runningCenter = Color(red: 0.22, green: 0.25, blue: 0.30)
    static let pausedCenter = Color(red: 0.32, green: 0.27, blue: 0.13)
    static let idleCenter = Color(red: 0.17, green: 0.20, blue: 0.25)
    static let finishedCenter = Color(red: 0.66, green: 0.10, blue: 0.12)

    static let runningEdge = Color(red: 0.08, green: 0.10, blue: 0.14)
    static let pausedEdge = Color(red: 0.12, green: 0.10, blue: 0.04)
    static let idleEdge = Color(red: 0.07, green: 0.09, blue: 0.12)
    static let finishedEdge = Color(red: 0.19, green: 0.02, blue: 0.04)
}
