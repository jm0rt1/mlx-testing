import Foundation

enum TaskStatus: String, CaseIterable, Codable, Identifiable {
    case active = "Active"
    case backlog = "Backlog"
    case maintenance = "Maintenance"
    case completed = "Completed"

    var id: String { rawValue }
}

struct TaskBoardItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var nextAction: String
    var tags: String
    var status: TaskStatus
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}
