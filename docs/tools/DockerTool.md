# DockerTool

**Category:** Developer Productivity
**Risk Level:** high
**Requires Approval:** Yes
**Tool Identifier:** `docker`

## Overview

`DockerTool` manages local Docker containers and images via the `docker` CLI. Container inspection and log viewing are lower risk; starting, stopping, removing containers, and executing commands inside them modify system state and are rated `high` risk. Requires Docker Desktop or OrbStack to be installed.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list`, `start`, `stop`, `remove`, `logs`, `exec`, `pull`, `images` |
| `container` | string | No | — | Container name or ID (required for `start`, `stop`, `remove`, `logs`, `exec`) |
| `image` | string | No | — | Image name with optional tag (for `pull`) |
| `command` | string | No | — | Shell command to execute inside the container (for `exec`) |
| `lines` | integer | No | `50` | Number of log lines to return (for `logs`) |

---

## Swift Implementation

```swift
import Foundation

struct DockerTool: AgentTool {

    let name = "docker"
    let toolDescription = "Manage Docker containers: list, start, stop, remove, view logs, run commands, and pull images."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",    type: .string, description: "list | start | stop | remove | logs | exec | pull | images",
                      required: true,
                      enumValues: ["list", "start", "stop", "remove", "logs", "exec", "pull", "images"]),
        ToolParameter(name: "container", type: .string,  description: "Container name or ID", required: false),
        ToolParameter(name: "image",     type: .string,  description: "Image name:tag",       required: false),
        ToolParameter(name: "command",   type: .string,  description: "Shell command for exec", required: false),
        ToolParameter(name: "lines",     type: .integer, description: "Log lines to return",  required: false, defaultValue: "50"),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .high

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }

        switch action {
        case "list":
            return run(["docker", "ps", "-a", "--format", "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"])
        case "images":
            return run(["docker", "images", "--format", "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"])
        case "start":
            guard let c = arguments["container"]?.stringValue else { throw ToolError.missingRequiredParameter("container") }
            return run(["docker", "start", c])
        case "stop":
            guard let c = arguments["container"]?.stringValue else { throw ToolError.missingRequiredParameter("container") }
            return run(["docker", "stop", c])
        case "remove":
            guard let c = arguments["container"]?.stringValue else { throw ToolError.missingRequiredParameter("container") }
            return run(["docker", "rm", c])
        case "logs":
            guard let c = arguments["container"]?.stringValue else { throw ToolError.missingRequiredParameter("container") }
            let lines: Int
            if case .integer(let l) = arguments["lines"] { lines = min(l, 500) } else { lines = 50 }
            return run(["docker", "logs", "--tail", "\(lines)", c], maxChars: 8_000)
        case "exec":
            guard let c = arguments["container"]?.stringValue else { throw ToolError.missingRequiredParameter("container") }
            guard let cmd = arguments["command"]?.stringValue else { throw ToolError.missingRequiredParameter("command") }
            return run(["docker", "exec", c, "/bin/sh", "-c", cmd], maxChars: 8_000)
        case "pull":
            guard let img = arguments["image"]?.stringValue else { throw ToolError.missingRequiredParameter("image") }
            return run(["docker", "pull", img], maxChars: 5_000)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Helper

    private func run(_ args: [String], maxChars: Int = 5_000) -> ToolResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin:/Applications/OrbStack.app/Contents/MacOS"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        try? p.run(); p.waitUntilExit()
        var output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if output.isEmpty { output = "(no output)" }
        if output.count > maxChars { output = String(output.prefix(maxChars)) + "\n... [truncated]" }
        return ToolResult(toolName: name, success: p.terminationStatus == 0, output: output)
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `docker` CLI (Docker Desktop or OrbStack) | All container and image operations |
| `--format` Go template | Concise table output from `docker ps` and `docker images` |

### Key Implementation Steps

1. **Docker discovery** — check common install locations (`/usr/local/bin/docker`, `/opt/homebrew/bin/docker`, OrbStack path) in `PATH`.
2. **list** — `docker ps -a` with a custom format template for a clean table.
3. **logs** — `docker logs --tail <N> <container>`. Cap at 500 lines and 8,000 characters.
4. **exec** — wrap the command in `/bin/sh -c` for shell feature support. Return combined stdout/stderr.
5. **pull** — fetches the image manifest and layers. Output can be verbose; truncate at 5,000 characters.

### Output Truncation

Variable by action: `logs` and `exec` → 8,000 chars; `pull` → 5,000 chars; others → 5,000 chars.

---

## Sandbox Entitlements

Running Docker requires executing a privileged daemon. No additional entitlements are needed in the app, but the user must have Docker Desktop or OrbStack installed and running.

---

## Example Tool Calls

```json
{"tool": "docker", "arguments": {"action": "list"}}
```

```json
{"tool": "docker", "arguments": {"action": "logs", "container": "my-api", "lines": 100}}
```

```json
{"tool": "docker", "arguments": {"action": "exec", "container": "my-db", "command": "psql -U postgres -c '\\dt'"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Docker daemon not running | `docker` returns `"Cannot connect to the Docker daemon"`, `success: false` |
| Container not found | `docker` returns `"No such container"`, `success: false` |
| Image pull requires auth | `docker pull` returns auth error; user must run `docker login` manually |

---

## Edge Cases

- **OrbStack vs Docker Desktop** — `docker` CLI is compatible with both; the socket path differs but the CLI auto-detects it.
- **Windows containers** — not applicable on macOS.
- **Resource limits** — `exec` can run arbitrary commands inside a container; this is why the tool is rated `high` risk.

---

## See Also

- [DatabaseTool](./DatabaseTool.md)
- [ShellCommandTool](../mlx-testing/AgentTools/ShellCommandTool.swift) *(existing)*
- [REPLTool](./REPLTool.md)
