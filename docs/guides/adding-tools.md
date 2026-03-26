# Adding New Agent Tools

> Step-by-step guide to creating and registering new tools in the agentic tool system.

---

## Overview

The MLX Copilot agent system lets the LLM invoke local tools during conversation. Tools conform to the `AgentTool` protocol and are registered in `ToolRegistry`. The LLM emits a `tool_call` JSON block, which `ToolExecutor` parses, validates, and executes.

This guide walks through creating a new tool from scratch.

---

## Step 1: Create the Tool File

Create a new Swift file in `mlx-testing/AgentTools/`:

```
mlx-testing/AgentTools/MyNewTool.swift
```

---

## Step 2: Implement the AgentTool Protocol

```swift
import Foundation

struct MyNewTool: AgentTool {
    // MARK: - Protocol Properties
    
    var name: String { "my_new_tool" }
    
    var toolDescription: String {
        "Brief description of what this tool does. The LLM reads this to decide when to use it."
    }
    
    var parameters: [ToolParameter] {
        [
            ToolParameter(
                name: "action",
                type: "string",
                description: "The action to perform",
                required: true,
                enumValues: ["read", "write", "list"]  // Fixed choices
            ),
            ToolParameter(
                name: "input",
                type: "string",
                description: "The input data to process",
                required: true
            ),
            ToolParameter(
                name: "verbose",
                type: "boolean",
                description: "Whether to include extra detail in the output",
                required: false  // Optional parameter
            )
        ]
    }
    
    var requiresApproval: Bool { true }
    
    var riskLevel: ToolRiskLevel { .medium }
    
    // MARK: - Execution
    
    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        // 1. Extract and validate arguments
        guard let action = arguments["action"]?.stringValue else {
            return ToolResult(
                toolName: name,
                success: false,
                output: "Missing required parameter: action",
                artifacts: []
            )
        }
        
        let input = arguments["input"]?.stringValue ?? ""
        let verbose = arguments["verbose"]?.boolValue ?? false
        
        // 2. Perform the action
        switch action {
        case "read":
            return try await performRead(input: input, verbose: verbose)
        case "write":
            return try await performWrite(input: input, verbose: verbose)
        case "list":
            return try await performList(verbose: verbose)
        default:
            return ToolResult(
                toolName: name,
                success: false,
                output: "Unknown action: \(action). Valid actions: read, write, list",
                artifacts: []
            )
        }
    }
    
    // MARK: - Private Helpers
    
    private func performRead(input: String, verbose: Bool) async throws -> ToolResult {
        // Your implementation here
        let output = "Read result for: \(input)"
        return ToolResult(
            toolName: name,
            success: true,
            output: verbose ? "Detailed: \(output)" : output,
            artifacts: []
        )
    }
    
    private func performWrite(input: String, verbose: Bool) async throws -> ToolResult {
        // Your implementation here
        return ToolResult(
            toolName: name,
            success: true,
            output: "Successfully wrote: \(input)",
            artifacts: [
                ToolArtifact(type: "file", value: "/path/to/written/file")
            ]
        )
    }
    
    private func performList(verbose: Bool) async throws -> ToolResult {
        // Your implementation here
        return ToolResult(
            toolName: name,
            success: true,
            output: "Listed items successfully",
            artifacts: []
        )
    }
}
```

---

## Step 3: Register the Tool

In `mlx-testing/AgentTools/ToolRegistry.swift`, add your tool to `registerDefaults()`:

```swift
func registerDefaults() {
    register(FileSystemTool())
    register(ShellCommandTool())
    register(ClipboardTool())
    register(AppLauncherTool())
    register(MyNewTool())          // ← Add here
}
```

---

## Step 4: Update Entitlements (if needed)

If your tool needs new sandbox permissions, update `mlx-testing/mlx_testing.entitlements`:

```xml
<key>com.apple.security.your-new-entitlement</key>
<true/>
```

Also update the entitlements tables in:
- `README.md` → Entitlements section
- `.github/copilot-instructions.md` → Entitlements section

---

## Step 5: Update Documentation

Update the README project structure tree to include the new file:

```
├── AgentTools/
│   ├── ...
│   └── MyNewTool.swift          — description of what it does
```

---

## Conventions & Best Practices

### Risk Levels

| Level | When to use | Examples |
|---|---|---|
| `.low` | Read-only, no side effects | Clipboard read, status check |
| `.medium` | Writes data, launches apps | File write, app launch, URL open |
| `.high` | Arbitrary execution, destructive ops | Shell commands, file deletion |

### Error Handling

- **Expected failures** (file not found, invalid input): Return `ToolResult(success: false, output: "error message")`
- **Unexpected failures** (system errors): Throw `ToolError` — the executor will catch and report it

```swift
// Expected failure — return a result
return ToolResult(toolName: name, success: false, output: "File not found: \(path)", artifacts: [])

// Unexpected failure — throw
throw ToolError.executionFailed("System error: \(error.localizedDescription)")
```

### Output Truncation

Large tool outputs must be truncated to prevent overwhelming the LLM's context window:

```swift
private let maxOutputChars = 5000

func truncateOutput(_ text: String) -> String {
    if text.count > maxOutputChars {
        return String(text.prefix(maxOutputChars)) + "\n\n[Output truncated at \(maxOutputChars) characters]"
    }
    return text
}
```

### Path Safety

Always resolve relative paths using `NSHomeDirectory()`:

```swift
func resolvePath(_ path: String) -> String {
    if path.hasPrefix("/") {
        return path
    }
    return NSHomeDirectory() + "/" + path
}
```

### Parameter Schemas

- Use `enumValues` for parameters with fixed choices
- Always mark required parameters with `required: true`
- Provide clear `description` strings — the LLM reads these to construct arguments

---

## How the LLM Calls Tools

When tools are enabled, the system prompt includes JSON schemas for all registered tools. The LLM generates a `tool_call` fenced block:

````
```tool_call
{"tool": "my_new_tool", "arguments": {"action": "read", "input": "data.txt"}}
```
````

`ToolExecutor.parseToolCall(from:)` extracts the JSON and routes to the registered tool's `execute()` method. The result is fed back into the conversation as a `toolResult` message, and the agentic loop continues.

---

## Example: Complete Tool — WebSearchTool

Here's a more complete example showing a hypothetical web search tool:

```swift
import Foundation

struct WebSearchTool: AgentTool {
    var name: String { "web_search" }
    var toolDescription: String { "Search the web using a query string and return top results" }
    var parameters: [ToolParameter] {
        [
            ToolParameter(name: "query", type: "string", description: "Search query", required: true),
            ToolParameter(name: "max_results", type: "integer", description: "Maximum results to return (1-10)", required: false)
        ]
    }
    var requiresApproval: Bool { true }
    var riskLevel: ToolRiskLevel { .low }
    
    private let maxOutputChars = 8000
    
    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let query = arguments["query"]?.stringValue, !query.isEmpty else {
            return ToolResult(toolName: name, success: false, output: "Missing or empty query", artifacts: [])
        }
        
        let maxResults = arguments["max_results"]?.intValue ?? 5
        let clampedMax = min(max(maxResults, 1), 10)
        
        // Perform search (implementation depends on search API)
        let results = try await performSearch(query: query, maxResults: clampedMax)
        
        var output = "Search results for: \"\(query)\"\n\n"
        for (i, result) in results.enumerated() {
            output += "\(i + 1). \(result.title)\n   \(result.url)\n   \(result.snippet)\n\n"
        }
        
        // Truncate if too long
        if output.count > maxOutputChars {
            output = String(output.prefix(maxOutputChars)) + "\n[Truncated]"
        }
        
        return ToolResult(
            toolName: name,
            success: true,
            output: output,
            artifacts: results.map { ToolArtifact(type: "url", value: $0.url) }
        )
    }
}
```

---

*Related: [Architecture — Agent System](../vision/05-architecture.md) · [Contributing Guide](contributing.md)*
