# REPLTool

**Category:** Developer Productivity
**Risk Level:** high
**Requires Approval:** Yes
**Tool Identifier:** `repl`

## Overview

`REPLTool` evaluates code snippets in sandboxed subprocesses, supporting Swift, Python 3, and JavaScript (via JavaScriptCore). Because it executes arbitrary code, it is rated `high` risk and always requires user approval. Useful for quick calculations, testing algorithms, or verifying snippets the LLM generates.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `language` | string | Yes | — | One of `swift`, `python`, `javascript` |
| `code` | string | Yes | — | The code snippet to evaluate |
| `timeout` | integer | No | `10` | Maximum execution time in seconds (max 30) |

---

## Swift Implementation

```swift
import Foundation
import JavaScriptCore

struct REPLTool: AgentTool {

    let name = "repl"
    let toolDescription = "Evaluate code snippets in a sandboxed process. Supports Swift, Python 3, and JavaScript."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "language", type: .string, description: "swift | python | javascript",
                      required: true, enumValues: ["swift", "python", "javascript"]),
        ToolParameter(name: "code",    type: .string,  description: "Code to evaluate", required: true),
        ToolParameter(name: "timeout", type: .integer, description: "Timeout in seconds (max 30)", required: false, defaultValue: "10"),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .high

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let language = arguments["language"]?.stringValue else { throw ToolError.missingRequiredParameter("language") }
        guard let code     = arguments["code"]?.stringValue     else { throw ToolError.missingRequiredParameter("code") }
        let timeout: Int
        if case .integer(let t) = arguments["timeout"] { timeout = min(t, 30) } else { timeout = 10 }

        switch language {
        case "swift":      return try await runSwift(code: code, timeout: timeout)
        case "python":     return try await runPython(code: code, timeout: timeout)
        case "javascript": return runJavaScript(code: code)
        default:
            throw ToolError.executionFailed("Unsupported language: \(language)")
        }
    }

    // MARK: - Swift

    private func runSwift(code: String, timeout: Int) async throws -> ToolResult {
        let dir = FileManager.default.temporaryDirectory
        let scriptURL = dir.appendingPathComponent("repl_\(UUID().uuidString).swift")
        try code.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        return await runProcess(["/usr/bin/swift", scriptURL.path], timeout: timeout)
    }

    // MARK: - Python

    private func runPython(code: String, timeout: Int) async throws -> ToolResult {
        let dir = FileManager.default.temporaryDirectory
        let scriptURL = dir.appendingPathComponent("repl_\(UUID().uuidString).py")
        try code.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        // Try python3 first, then python
        for pythonPath in ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"] {
            if FileManager.default.fileExists(atPath: pythonPath) {
                return await runProcess([pythonPath, scriptURL.path], timeout: timeout)
            }
        }
        return ToolResult(toolName: name, success: false, output: "Python 3 not found. Install via Homebrew: brew install python")
    }

    // MARK: - JavaScript (in-process via JavaScriptCore)

    private func runJavaScript(code: String) -> ToolResult {
        let context = JSContext()!
        context.exceptionHandler = { _, exception in
            // exceptions are captured via context.exception
        }

        // Capture console.log output
        var output: [String] = []
        let consoleLog: @convention(block) (String) -> Void = { message in
            output.append(message)
        }
        context.setObject(consoleLog, forKeyedSubscript: "print" as NSString)
        context.evaluateScript("var console = { log: print, error: print };")

        let result = context.evaluateScript(code)
        if let exception = context.exception {
            return ToolResult(toolName: name, success: false, output: "JS error: \(exception)")
        }

        var parts: [String] = []
        if !output.isEmpty { parts.append("Output:\n" + output.joined(separator: "\n")) }
        if let r = result, !r.isUndefined, !r.isNull { parts.append("Return value: \(r)") }
        let text = parts.isEmpty ? "(no output)" : parts.joined(separator: "\n\n")
        return ToolResult(toolName: name, success: true, output: text)
    }

    // MARK: - Process Runner

    private func runProcess(_ args: [String], timeout: Int) async -> ToolResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin"
        p.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError  = errPipe

        do { try p.run() } catch {
            return ToolResult(toolName: name, success: false, output: "Launch failed: \(error)")
        }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            if p.isRunning { p.terminate() }
        }
        p.waitUntilExit()
        timeoutTask.cancel()

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let maxChars = 5_000
        var output = ""
        if !stdout.isEmpty { output += stdout.count > maxChars ? String(stdout.prefix(maxChars)) + "\n... [truncated]" : stdout }
        if !stderr.isEmpty { output += "\n[stderr]\n" + (stderr.count > maxChars ? String(stderr.prefix(maxChars)) : stderr) }
        return ToolResult(toolName: name, success: p.terminationStatus == 0, output: output.isEmpty ? "(no output)" : output)
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `/usr/bin/swift` | Swift script evaluation |
| `python3` CLI | Python 3 script evaluation |
| `JavaScriptCore` — `JSContext` | In-process JavaScript evaluation |
| `FileManager.temporaryDirectory` | Temp script files for Swift and Python |

### Key Implementation Steps

1. **Swift** — write code to a `.swift` temp file, run `/usr/bin/swift <file>` with a timeout.
2. **Python** — probe common Python 3 paths, write to a `.py` temp file, run it.
3. **JavaScript** — use `JSContext` in-process (no subprocess overhead). Redirect `console.log` to a captured array. Return both captured output and the return value.
4. **Timeout** — for subprocess languages, cancel with `p.terminate()` after `timeout` seconds.
5. **Output cap** — truncate stdout/stderr at 5,000 characters.

### Output Truncation

`maxChars = 5_000` per stream (stdout and stderr independently).

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.files.absolute-path.read-write` | Write/execute temp script files in `/tmp` |

---

## Example Tool Calls

```json
{"tool": "repl", "arguments": {"language": "swift", "code": "import Foundation\nprint(Date())"}}
```

```json
{"tool": "repl", "arguments": {"language": "javascript", "code": "const fib = n => n <= 1 ? n : fib(n-1)+fib(n-2); console.log(fib(10))"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Syntax error in code | Compiler/interpreter prints error to stderr; returned in output |
| Timeout exceeded | Process terminated; output contains whatever was printed before timeout |
| Python not found | Returns install instructions |

---

## Edge Cases

- **Infinite loops** — handled by the timeout parameter.
- **Network access from snippets** — not blocked, but network calls in sandboxed apps may fail due to entitlements.
- **JavaScript** — `JSContext` runs synchronously; promises and async code are not directly supported.

---

## See Also

- [ShellCommandTool](../mlx-testing/AgentTools/ShellCommandTool.swift) *(existing)*
- [XcodeTool](./XcodeTool.md)
