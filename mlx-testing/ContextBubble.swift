import Foundation

// MARK: - ContextBubble

/// A toggleable block of context injected into the system prompt.
/// Can represent skills, instructions, memory, or custom user context.
struct ContextBubble: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var content: String
    var type: BubbleType
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        type: BubbleType = .custom,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.type = type
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The kind of context this bubble provides.
    enum BubbleType: String, Codable, CaseIterable, Identifiable {
        case skill        // e.g. "You are an expert Swift developer"
        case instruction  // e.g. "Always respond in bullet points"
        case memory       // e.g. "User's name is James, uses a Mac"
        case custom       // free-form user context

        var id: String { rawValue }

        var label: String {
            switch self {
            case .skill:       return "Skill"
            case .instruction: return "Instruction"
            case .memory:      return "Memory"
            case .custom:      return "Custom"
            }
        }

        var icon: String {
            switch self {
            case .skill:       return "star.fill"
            case .instruction: return "list.bullet.rectangle"
            case .memory:      return "brain.head.profile"
            case .custom:      return "bubble.left.fill"
            }
        }
    }
}

// MARK: - Defaults

extension ContextBubble {
    /// Built-in starter bubbles shipped with the app.
    static let defaults: [ContextBubble] = [
        ContextBubble(
            name: "Swift Expert",
            content: "You are an expert Swift and SwiftUI developer on macOS and iOS. Prefer modern Swift concurrency (async/await), value types, and protocol-oriented design.",
            type: .skill,
            isEnabled: false
        ),
        ContextBubble(
            name: "Concise Responses",
            content: "Keep your responses concise and to the point. Use bullet points for lists. Avoid unnecessary preamble.",
            type: .instruction,
            isEnabled: true
        ),
        ContextBubble(
            name: "User Info",
            content: "The user's name is James. They use a Mac with Apple Silicon and 24 GB of unified memory.",
            type: .memory,
            isEnabled: false
        ),
    ]
}
