import Foundation

struct TimerGroup: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    var timerIDs: [UUID]
}
