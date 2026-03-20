import Foundation

struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    let role: Role
    var text: String
    let date: Date

    init(id: UUID = UUID(), role: Role, text: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }
}
