import Combine
import Foundation

// MARK: - Tool Registry

/// Central registry of all available tools. Tools register themselves here,
/// and the system prompt generator + executor query this registry.
///
/// **To add a new tool:**
/// ```swift
/// ToolRegistry.shared.register(MyNewTool())
/// ```
@MainActor
final class ToolRegistry: ObservableObject {

    static let shared = ToolRegistry()

    @Published private(set) var tools: [String: any AgentTool] = [:]

    /// Tools the user has permanently approved (by name).
    @Published var alwaysApproved: Set<String> = [] {
        didSet { persistApprovals() }
    }

    /// Tools the user has individually disabled (by name).
    @Published var disabledTools: Set<String> = [] {
        didSet { persistDisabledTools() }
    }

    private let approvalsKey = "tool_always_approved"
    private let disabledToolsKey = "tool_disabled"

    private init() {
        loadApprovals()
        loadDisabledTools()
    }

    // MARK: - Registration

    func register(_ tool: any AgentTool) {
        tools[tool.name] = tool
    }

    func unregister(_ name: String) {
        tools.removeValue(forKey: name)
    }

    func tool(named name: String) -> (any AgentTool)? {
        tools[name]
    }

    /// Register all built-in tools. Call once at app startup.
    func registerDefaults() {
        register(FileSystemTool())
        register(ShellCommandTool())
        register(ClipboardTool())
        register(AppLauncherTool())
        register(CalendarTool())
    }

    // MARK: - Per-Tool Enable/Disable

    func isToolEnabled(_ name: String) -> Bool {
        !disabledTools.contains(name)
    }

    func setToolEnabled(_ name: String, enabled: Bool) {
        if enabled {
            disabledTools.remove(name)
        } else {
            disabledTools.insert(name)
        }
    }

    /// Number of tools currently enabled.
    var enabledToolCount: Int {
        tools.keys.filter { !disabledTools.contains($0) }.count
    }

    /// Only tools that are currently enabled.
    var enabledTools: [String: any AgentTool] {
        tools.filter { !disabledTools.contains($0.key) }
    }

    // MARK: - Schema Generation

    /// Generates the tool description block to inject into the system prompt.
    /// Only includes enabled tools.
    func toolSchemaPrompt() -> String {
        let active = enabledTools
        guard !active.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("/no_think")
        lines.append("")
        lines.append("[Available Tools]")
        lines.append("You have access to tools you can call. To call a tool, output ONLY a JSON code block like this:")
        lines.append("")
        lines.append("```tool_call")
        lines.append(#"{"tool": "tool_name", "arguments": {"param1": "value1"}}"#)
        lines.append("```")
        lines.append("")
        lines.append("RULES:")
        lines.append("- You MUST wrap the JSON in ```tool_call and ``` markers exactly as shown above.")
        lines.append("- Do NOT output the JSON inline or without the code fence.")
        lines.append("- Only use ONE tool_call block per response.")
        lines.append("- Do NOT explain your reasoning before a tool call. Just output the tool_call block.")
        lines.append("- After receiving a tool result, respond to the user naturally or make another tool call.")
        lines.append("")

        let sortedTools = active.values.sorted { $0.name < $1.name }
        for tool in sortedTools {
            lines.append("### \(tool.name)")
            lines.append(tool.toolDescription)
            lines.append("Risk: \(tool.riskLevel.rawValue)")
            if !tool.parameters.isEmpty {
                lines.append("Parameters:")
                for param in tool.parameters {
                    let req = param.required ? "(required)" : "(optional)"
                    var line = "  - \(param.name) [\(param.type.rawValue)] \(req): \(param.description)"
                    if let def = param.defaultValue {
                        line += " (default: \(def))"
                    }
                    if let enums = param.enumValues {
                        line += " (values: \(enums.joined(separator: ", ")))"
                    }
                    lines.append(line)
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Approval Persistence

    private func persistApprovals() {
        UserDefaults.standard.set(Array(alwaysApproved), forKey: approvalsKey)
    }

    private func loadApprovals() {
        if let saved = UserDefaults.standard.stringArray(forKey: approvalsKey) {
            alwaysApproved = Set(saved)
        }
    }

    // MARK: - Disabled Tools Persistence

    private func persistDisabledTools() {
        UserDefaults.standard.set(Array(disabledTools), forKey: disabledToolsKey)
    }

    private func loadDisabledTools() {
        if let saved = UserDefaults.standard.stringArray(forKey: disabledToolsKey) {
            disabledTools = Set(saved)
        }
    }

    func needsApproval(for toolName: String) -> Bool {
        guard let tool = tools[toolName] else { return true }
        if alwaysApproved.contains(toolName) { return false }
        return tool.requiresApproval
    }
}
