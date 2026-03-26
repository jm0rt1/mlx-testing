import Foundation

// MARK: - Tool Protocol

/// Any capability the LLM can invoke. Conform to this protocol to create new tools.
///
/// **How to add a new tool:**
/// 1. Create a struct conforming to `AgentTool`
/// 2. Define its `name`, `description`, and `parameters` schema
/// 3. Implement `execute(arguments:)` to perform the action
/// 4. Register it in `ToolRegistry.shared.registerDefaults()`
///
protocol AgentTool {
    /// Unique identifier used in tool_call JSON, e.g. "read_file"
    var name: String { get }

    /// Human-readable description shown to the LLM in the system prompt
    var toolDescription: String { get }

    /// JSON-Schema-style parameter definitions for the LLM
    var parameters: [ToolParameter] { get }

    /// Whether this tool requires user approval before executing
    var requiresApproval: Bool { get }

    /// The risk level — determines UI treatment
    var riskLevel: ToolRiskLevel { get }

    /// Execute the tool with the given arguments. Returns a result string.
    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult
}

// MARK: - Parameter Definition

/// Describes one parameter of a tool — used to generate the schema injected into the system prompt.
struct ToolParameter: Codable, Hashable {
    let name: String
    let type: ParameterType
    let description: String
    let required: Bool
    let defaultValue: String?
    let enumValues: [String]?

    init(
        name: String,
        type: ParameterType,
        description: String,
        required: Bool = true,
        defaultValue: String? = nil,
        enumValues: [String]? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.defaultValue = defaultValue
        self.enumValues = enumValues
    }

    enum ParameterType: String, Codable {
        case string
        case integer
        case boolean
        case array
    }
}

// MARK: - Argument Value

/// A loosely-typed value parsed from the LLM's JSON tool call.
enum ToolArgumentValue: Codable, CustomStringConvertible {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case array([String])

    var stringValue: String {
        switch self {
        case .string(let s):  return s
        case .integer(let i): return String(i)
        case .boolean(let b): return String(b)
        case .array(let a):   return a.joined(separator: ", ")
        }
    }

    var description: String { stringValue }

    // Custom Codable to handle JSON heterogeneity
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let i = try? container.decode(Int.self) {
            self = .integer(i)
        } else if let b = try? container.decode(Bool.self) {
            self = .boolean(b)
        } else if let a = try? container.decode([String].self) {
            self = .array(a)
        } else {
            throw DecodingError.typeMismatch(
                ToolArgumentValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported argument type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):  try container.encode(s)
        case .integer(let i): try container.encode(i)
        case .boolean(let b): try container.encode(b)
        case .array(let a):   try container.encode(a)
        }
    }
}

// MARK: - Tool Call (parsed from LLM output)

/// Represents a tool invocation parsed from the model's response.
struct ToolCall: Identifiable, Codable {
    let id: UUID
    let toolName: String
    let arguments: [String: ToolArgumentValue]

    init(id: UUID = UUID(), toolName: String, arguments: [String: ToolArgumentValue]) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
    }

    // Codable keys to match the JSON the LLM produces
    enum CodingKeys: String, CodingKey {
        case id
        case toolName = "tool"
        case arguments
    }
}

// MARK: - Tool Result

/// The outcome of executing a tool.
struct ToolResult {
    let toolName: String
    let success: Bool
    let output: String
    let artifacts: [ToolArtifact]

    init(toolName: String, success: Bool, output: String, artifacts: [ToolArtifact] = []) {
        self.toolName = toolName
        self.success = success
        self.output = output
        self.artifacts = artifacts
    }
}

/// An optional artifact produced by a tool (file path, URL, data, etc.)
struct ToolArtifact {
    let type: ArtifactType
    let label: String
    let value: String

    enum ArtifactType {
        case filePath
        case url
        case text
        case code
    }
}

// MARK: - Risk Level

/// Determines how much caution the UI applies before executing a tool.
enum ToolRiskLevel: String, Codable, Comparable {
    case low      // e.g. reading clipboard, listing files
    case medium   // e.g. writing files, launching apps
    case high     // e.g. running shell commands

    private var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    static func < (lhs: ToolRiskLevel, rhs: ToolRiskLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Tool Errors

enum ToolError: LocalizedError {
    case toolNotFound(String)
    case missingRequiredParameter(String)
    case executionFailed(String)
    case denied

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):           return "Unknown tool: \(name)"
        case .missingRequiredParameter(let p):  return "Missing required parameter: \(p)"
        case .executionFailed(let reason):       return "Tool execution failed: \(reason)"
        case .denied:                            return "Tool execution denied by user"
        }
    }
}
