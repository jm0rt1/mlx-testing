import Foundation

struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    let role: Role
    var text: String
    let date: Date

    /// If this message represents a tool call, store the parsed call info.
    var toolCall: ToolCallInfo?

    /// If this message is a tool result, store the result info.
    var toolResult: ToolResultInfo?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        date: Date = Date(),
        toolCall: ToolCallInfo? = nil,
        toolResult: ToolResultInfo? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.toolCall = toolCall
        self.toolResult = toolResult
    }

    enum Role: String, Codable {
        case user
        case assistant
        case system
        case toolCall      // assistant requested a tool
        case toolResult    // system returning tool output
    }

    // MARK: - Hashable (exclude non-Hashable stored tool data for diffing)

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Tool Call Info (lightweight, Hashable-safe)

struct ToolCallInfo {
    let toolName: String
    let arguments: [String: String] // flattened for display
    var status: ToolCallStatus

    enum ToolCallStatus {
        case pending       // awaiting approval
        case approved      // user approved, executing
        case executing     // currently running
        case completed     // finished
        case denied        // user denied
        case failed        // execution error
    }
}

struct ToolResultInfo {
    let toolName: String
    let success: Bool
    let output: String
    let artifacts: [ToolArtifact]
}
