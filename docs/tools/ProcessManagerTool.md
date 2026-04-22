# ProcessManagerTool

**Category:** macOS System & Hardware
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `process_manager`

## Overview

`ProcessManagerTool` lets the LLM inspect and control running processes. Listing and querying processes is read-only (low impact), but terminating a process is destructive and always requires user approval. Typical uses include finding which app is consuming CPU, checking whether a background daemon is running, or killing a hung process.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list`, `kill`, `find_by_port`, `info` |
| `pid` | integer | No | — | Process ID (required for `kill` and `info`) |
| `name` | string | No | — | Process name filter for `list`; name to kill for `kill` |
| `port` | integer | No | — | TCP/UDP port number for `find_by_port` |

---

## Swift Implementation

```swift
import Foundation

struct ProcessManagerTool: AgentTool {

    let name = "process_manager"
    let toolDescription = "List, inspect, and terminate running macOS processes."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action", type: .string,
                      description: "Operation to perform",
                      required: true,
                      enumValues: ["list", "kill", "find_by_port", "info"]),
        ToolParameter(name: "pid",  type: .integer, description: "Process ID",   required: false),
        ToolParameter(name: "name", type: .string,  description: "Process name filter", required: false),
        ToolParameter(name: "port", type: .integer, description: "Port number for find_by_port", required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        switch action {
        case "list":        return try listProcesses(filter: arguments["name"]?.stringValue)
        case "kill":        return try killProcess(arguments: arguments)
        case "find_by_port": return try findByPort(arguments: arguments)
        case "info":        return try processInfo(arguments: arguments)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    /// Returns a formatted table of running processes, optionally filtered by name.
    private func listProcesses(filter: String?) throws -> ToolResult {
        // Use `ps -eo pid,pcpu,pmem,comm` via Process, parse output into rows.
        // Filter rows where the command column contains the name filter (case-insensitive).
        let result = try runShell("ps -eo pid,pcpu,pmem,comm")
        let lines = result.components(separatedBy: "\n")
        let filtered: [String]
        if let f = filter?.lowercased(), !f.isEmpty {
            filtered = lines.filter { $0.lowercased().contains(f) }
        } else {
            filtered = lines
        }
        let maxChars = 8_000
        var output = filtered.joined(separator: "\n")
        if output.count > maxChars { output = String(output.prefix(maxChars)) + "\n... [truncated]" }
        return ToolResult(toolName: name, success: true, output: output)
    }

    /// Kills a process identified by PID or name.
    private func killProcess(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        if case .integer(let pid) = arguments["pid"] {
            let result = try runShell("kill -TERM \(pid)")
            return ToolResult(toolName: name, success: true, output: "Sent SIGTERM to PID \(pid).\n\(result)")
        } else if let name = arguments["name"]?.stringValue {
            let result = try runShell("pkill -TERM -x '\(name)'")
            return ToolResult(toolName: name, success: true, output: "Sent SIGTERM to '\(name)'.\n\(result)")
        }
        throw ToolError.missingRequiredParameter("pid or name")
    }

    /// Lists PIDs listening on a given port using `lsof`.
    private func findByPort(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard case .integer(let port) = arguments["port"] else {
            throw ToolError.missingRequiredParameter("port")
        }
        let output = try runShell("lsof -i :\(port) -sTCP:LISTEN -n -P")
        return ToolResult(toolName: name, success: true, output: output.isEmpty ? "No process listening on port \(port)" : output)
    }

    /// Returns detailed info for a single PID.
    private func processInfo(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard case .integer(let pid) = arguments["pid"] else {
            throw ToolError.missingRequiredParameter("pid")
        }
        let output = try runShell("ps -p \(pid) -o pid,ppid,pcpu,pmem,rss,vsz,lstart,comm")
        return ToolResult(toolName: name, success: true, output: output)
    }

    // MARK: - Helper

    private func runShell(_ command: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        try p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `/bin/bash` via `Process` | Run `ps`, `kill`, `lsof`, `pkill` |
| Darwin `kill(2)` syscall | Can be called directly instead of via shell for SIGTERM/SIGKILL |
| `NSRunningApplication` | Alternative to `ps` for GUI applications only |

### Key Implementation Steps

1. **List** — shell out to `ps -eo pid,pcpu,pmem,comm` and parse lines. Apply an optional case-insensitive filter on the `comm` column. Cap output at 8,000 characters.
2. **Kill** — prefer PID-based kill (`kill -TERM <pid>`) for precision. Name-based kill uses `pkill -x` (exact match) to avoid accidentally killing unrelated processes. Always default to `SIGTERM`; only send `SIGKILL` if the user explicitly requests it.
3. **Find by port** — run `lsof -i :<port> -sTCP:LISTEN -n -P`. Parse the `PID` and `COMMAND` columns.
4. **Info** — run `ps -p <pid> -o pid,ppid,pcpu,pmem,rss,vsz,lstart,comm` for a single process snapshot.

### Output Truncation

`listProcesses` caps output at `maxChars = 8_000` and appends `"... [truncated]"`.

---

## Sandbox Entitlements

No additional entitlements required. `Process` is available in sandboxed apps when running from a user-selected path or system binary. `/bin/bash` is accessible. `lsof` and `ps` require no special privilege beyond standard user access.

> **Note:** Killing processes owned by other users or system daemons will fail with `EPERM`. The tool returns the shell error in that case.

---

## Example Tool Calls

```json
{"tool": "process_manager", "arguments": {"action": "list", "name": "Safari"}}
```

```json
{"tool": "process_manager", "arguments": {"action": "kill", "pid": 1234}}
```

```json
{"tool": "process_manager", "arguments": {"action": "find_by_port", "port": 8080}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Missing `pid` for `kill` when no `name` given | Throws `ToolError.missingRequiredParameter("pid or name")` |
| `kill` returns `EPERM` | Returns `success: false` with shell stderr output |
| PID does not exist | `ps -p <pid>` returns empty; return `"No process with PID <pid>"` |
| `lsof` not found | Catch `Process` launch error; return `success: false` with message |

---

## Edge Cases

- **Zombie processes** — listed in `ps` with state `Z`; `kill` returns success but has no effect. Add a note in the output.
- **Rapid PID reuse** — between list and kill, a different process may have taken the PID. Always show the process name alongside the PID before confirming kill.
- **System Integrity Protection (SIP)** — cannot kill system-protected processes. Return the shell's `Operation not permitted` error.
- **pkill scope** — `pkill -x` matches the exact executable name across all user processes; it may kill multiple instances of an app. Prefer PID-based kill when possible.

---

## See Also

- [SystemInfoTool](./SystemInfoTool.md)
- [ShellCommandTool](../mlx-testing/AgentTools/ShellCommandTool.swift) *(existing)*
