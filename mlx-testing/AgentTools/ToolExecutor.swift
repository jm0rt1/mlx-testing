import Combine
import Foundation

// MARK: - Tool Executor

/// Parses tool calls from LLM output, executes them, and returns results.
/// This is the bridge between the LLM conversation loop and the tool system.
@MainActor
final class ToolExecutor: ObservableObject {

    let registry: ToolRegistry

    /// The pending tool call awaiting user approval (if any).
    @Published var pendingApproval: ToolCall?

    /// History of all tool calls and results in this session.
    @Published private(set) var history: [ToolExecutionRecord] = []

    init(registry: ToolRegistry = .shared) {
        self.registry = registry
    }

    // MARK: - Parsing

    /// Scans the LLM's response text for a ```tool_call``` JSON block.
    /// Returns the parsed ToolCall if found, nil otherwise.
    func parseToolCall(from text: String) -> ToolCall? {
        // Look for ```tool_call ... ``` blocks
        let patterns: [String] = [
            #"```tool_call\s*\n([\s\S]*?)\n\s*```"#,   // fenced with tool_call tag
            #"```json\s*\n(\{[\s\S]*?"tool"[\s\S]*?\})\s*\n\s*```"#,  // fenced json with "tool" key
            #"```\s*\n(\{[\s\S]*?"tool"[\s\S]*?\})\s*\n\s*```"#,      // plain fenced with "tool" key
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else {
                continue
            }

            let jsonString = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = jsonString.data(using: .utf8) else { continue }

            do {
                let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
                return decoded
            } catch {
                print("[ToolExecutor] Failed to decode tool call: \(error)")
                print("[ToolExecutor] JSON was: \(jsonString)")
                continue
            }
        }

        return nil
    }

    /// Extracts the "prose" portion of the response (everything outside the tool_call block).
    func extractProse(from text: String) -> String {
        var result = text

        let patterns: [String] = [
            #"```tool_call\s*\n[\s\S]*?\n\s*```"#,
            #"```json\s*\n\{[\s\S]*?"tool"[\s\S]*?\}\s*\n\s*```"#,
            #"```\s*\n\{[\s\S]*?"tool"[\s\S]*?\}\s*\n\s*```"#,
        ]

        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Execution

    /// Execute a tool call. Checks approval status first.
    /// If approval is needed and not granted, sets `pendingApproval` and throws `.denied`.
    func execute(_ call: ToolCall) async throws -> ToolResult {
        guard let tool = registry.tool(named: call.toolName) else {
            let result = ToolResult(
                toolName: call.toolName,
                success: false,
                output: "Tool '\(call.toolName)' not found. Available tools: \(registry.tools.keys.sorted().joined(separator: ", "))"
            )
            record(call: call, result: result)
            throw ToolError.toolNotFound(call.toolName)
        }

        // Validate required parameters
        for param in tool.parameters where param.required {
            guard call.arguments[param.name] != nil else {
                let result = ToolResult(
                    toolName: call.toolName,
                    success: false,
                    output: "Missing required parameter: \(param.name)"
                )
                record(call: call, result: result)
                throw ToolError.missingRequiredParameter(param.name)
            }
        }

        // Execute
        do {
            let result = try await tool.execute(arguments: call.arguments)
            record(call: call, result: result)
            return result
        } catch {
            let result = ToolResult(
                toolName: call.toolName,
                success: false,
                output: "Execution error: \(error.localizedDescription)"
            )
            record(call: call, result: result)
            throw error
        }
    }

    // MARK: - History

    private func record(call: ToolCall, result: ToolResult) {
        let record = ToolExecutionRecord(
            call: call,
            result: result,
            timestamp: Date()
        )
        history.append(record)
    }

    func clearHistory() {
        history = []
    }
}

// MARK: - Execution Record

struct ToolExecutionRecord: Identifiable {
    let id = UUID()
    let call: ToolCall
    let result: ToolResult
    let timestamp: Date
}
