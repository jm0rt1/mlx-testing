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

    /// Scans the LLM's response text for a tool call.
    /// Tries multiple patterns from strict (fenced) to lenient (bare JSON).
    func parseToolCall(from text: String) -> ToolCall? {
        print("[ToolParser] Parsing \(text.count) chars")
        print("[ToolParser] Text: \(text.prefix(300))")

        // Strategy 1: fenced ```tool_call ... ```
        // Strategy 2: fenced ```json ... ``` with "tool" key
        // Strategy 3: fenced ``` ... ``` with "tool" key
        // Strategy 4: bare inline JSON {"tool": ...}
        // Strategy 5: tool_call{...} (no space, model smashes them together)
        let fencedPatterns: [(String, String)] = [
            ("fenced tool_call", #"```tool_call\s*\n?([\s\S]*?)\n?\s*```"#),
            ("fenced json+tool", #"```json\s*\n?(\{[\s\S]*?"tool"[\s\S]*?\})\s*\n?\s*```"#),
            ("fenced bare+tool", #"```\s*\n?(\{[\s\S]*?"tool"[\s\S]*?\})\s*\n?\s*```"#),
        ]

        for (label, pattern) in fencedPatterns {
            print("[ToolParser] Trying: \(label)")
            if let call = tryParse(text: text, pattern: pattern) {
                print("[ToolParser] ✅ Matched: \(label) → \(call.toolName)")
                return call
            }
        }

        // Strategy 4: bare JSON object with "tool" key anywhere in the text
        let barePatterns: [(String, String)] = [
            ("bare JSON full", #"(\{[^{}]*"tool"\s*:\s*"[^"]+"\s*,\s*"arguments"\s*:\s*\{[^{}]*\}\s*\})"#),
            ("bare JSON simple", #"(\{[^{}]*"tool"\s*:\s*"[^"]+"[^{}]*\})"#),
        ]

        for (label, pattern) in barePatterns {
            print("[ToolParser] Trying: \(label)")
            if let call = tryParse(text: text, pattern: pattern) {
                print("[ToolParser] ✅ Matched: \(label) → \(call.toolName)")
                return call
            }
        }

        // Strategy 5: tool_call smashed onto JSON like tool_call{"tool":...}
        let smashedPattern = #"tool_call\s*(\{[\s\S]*?"tool"[\s\S]*?\})"#
        print("[ToolParser] Trying: smashed")
        if let call = tryParse(text: text, pattern: smashedPattern) {
            print("[ToolParser] ✅ Matched: smashed → \(call.toolName)")
            return call
        }

        print("[ToolParser] ❌ No pattern matched")
        return nil
    }

    /// Attempts to extract and decode a ToolCall using the given regex pattern.
    private func tryParse(text: String, pattern: String) -> ToolCall? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            print("[ToolParser]   regex compile failed")
            return nil
        }

        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            print("[ToolParser]   no regex match")
            return nil
        }

        guard match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            print("[ToolParser]   no capture group")
            return nil
        }

        let jsonString = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        print("[ToolParser]   captured JSON (\(jsonString.count) chars): \(jsonString.prefix(200))")

        guard let data = jsonString.data(using: .utf8) else {
            print("[ToolParser]   failed to convert to data")
            return nil
        }

        do {
            let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
            return decoded
        } catch {
            print("[ToolParser]   JSON decode error: \(error)")
            print("[ToolParser]   JSON was: \(jsonString)")
            return nil
        }
    }

    /// Extracts the "prose" portion of the response (everything outside tool call blocks).
    func extractProse(from text: String) -> String {
        var result = text

        // Remove all forms of tool call blocks
        let removalPatterns: [String] = [
            #"```tool_call\s*\n?[\s\S]*?\n?\s*```"#,
            #"```json\s*\n?\{[\s\S]*?"tool"[\s\S]*?\}\s*\n?\s*```"#,
            #"```\s*\n?\{[\s\S]*?"tool"[\s\S]*?\}\s*\n?\s*```"#,
            #"tool_call\s*\{[^{}]*"tool"\s*:\s*"[^"]+"\s*,\s*"arguments"\s*:\s*\{[^{}]*\}\s*\}"#,
            #"\{[^{}]*"tool"\s*:\s*"[^"]+"\s*,\s*"arguments"\s*:\s*\{[^{}]*\}\s*\}"#,
        ]

        for pattern in removalPatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Execution

    /// Execute a tool call. Validates the tool is enabled and parameters then runs the tool.
    func execute(_ call: ToolCall) async throws -> ToolResult {
        // Check if the tool is enabled
        guard registry.isToolEnabled(call.toolName) else {
            let result = ToolResult(
                toolName: call.toolName,
                success: false,
                output: "Tool '\(call.toolName)' is currently disabled."
            )
            record(call: call, result: result)
            throw ToolError.toolNotFound(call.toolName)
        }

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
