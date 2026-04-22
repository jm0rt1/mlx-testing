import AppKit
import Foundation

// MARK: - Clipboard Tool

/// Lets the LLM read from and write to the system clipboard (pasteboard).
struct ClipboardTool: AgentTool {

    let name = "clipboard"

    let toolDescription = """
        Interact with the system clipboard (pasteboard). \
        Can read the current clipboard text content or write new text to the clipboard. \
        Useful for transferring data between the chat and other applications.
        """

    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: .string,
            description: "The operation to perform",
            required: true,
            enumValues: ["read", "write"]
        ),
        ToolParameter(
            name: "content",
            type: .string,
            description: "Text to copy to clipboard (required for 'write' action)",
            required: false
        ),
    ]

    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }

        switch action {
        case "read":
            return readClipboard()
        case "write":
            guard let content = arguments["content"]?.stringValue else {
                throw ToolError.missingRequiredParameter("content")
            }
            return writeClipboard(content)
        default:
            throw ToolError.executionFailed("Unknown action: \(action). Use: read, write")
        }
    }

    private func readClipboard() -> ToolResult {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) {
            // Truncate very long clipboard content
            let maxChars = 5_000
            let truncated = text.count > maxChars
            let output = truncated
                ? String(text.prefix(maxChars)) + "\n\n... [truncated, \(text.count) total characters]"
                : text

            return ToolResult(
                toolName: name,
                success: true,
                output: "Clipboard contents:\n\(output)"
            )
        } else {
            return ToolResult(
                toolName: name,
                success: true,
                output: "Clipboard is empty or contains non-text content."
            )
        }
    }

    private func writeClipboard(_ content: String) -> ToolResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        return ToolResult(
            toolName: name,
            success: true,
            output: "Copied \(content.count) characters to clipboard."
        )
    }
}
