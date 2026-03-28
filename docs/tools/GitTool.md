# GitTool

**Category:** Developer Productivity
**Risk Level:** medium
**Requires Approval:** Yes (for mutating actions)
**Tool Identifier:** `git`

## Overview

`GitTool` runs common Git operations against any local repository. Read-only operations (`status`, `log`, `diff`, `blame`) are low-impact and could be auto-approved; mutating operations (`commit`, `push`, `checkout`, `stash`) require explicit approval. This tool enables the LLM to inspect repository state and assist with code review, changelog generation, and automated commits.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `status`, `diff`, `log`, `blame`, `commit`, `push`, `checkout`, `stash`, `branch`, `show` |
| `repo_path` | string | No | `~` | Path to the git repository root |
| `path` | string | No | — | File or directory path (for `diff`, `blame`) |
| `message` | string | No | — | Commit message (for `commit`) |
| `branch` | string | No | — | Branch name (for `checkout`, `branch`) |
| `ref` | string | No | `HEAD` | Commit SHA, branch, or tag (for `show`, `log`) |
| `limit` | integer | No | `20` | Maximum number of log entries |

---

## Swift Implementation

```swift
import Foundation

struct GitTool: AgentTool {

    let name = "git"
    let toolDescription = "Run Git operations: status, diff, log, blame, commit, push, checkout, stash, branch."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",    type: .string,  description: "Git operation",
                      required: true,
                      enumValues: ["status", "diff", "log", "blame", "commit", "push",
                                   "checkout", "stash", "branch", "show"]),
        ToolParameter(name: "repo_path", type: .string,  description: "Repository root path", required: false),
        ToolParameter(name: "path",      type: .string,  description: "File/dir path",        required: false),
        ToolParameter(name: "message",   type: .string,  description: "Commit message",       required: false),
        ToolParameter(name: "branch",    type: .string,  description: "Branch name",          required: false),
        ToolParameter(name: "ref",       type: .string,  description: "Commit/branch/tag ref", required: false, defaultValue: "HEAD"),
        ToolParameter(name: "limit",     type: .integer, description: "Log entry limit",      required: false, defaultValue: "20"),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        let repoPath = resolvedRepoPath(arguments["repo_path"]?.stringValue)
        let limit: Int
        if case .integer(let l) = arguments["limit"] { limit = min(l, 100) } else { limit = 20 }

        switch action {
        case "status":
            return run(["git", "-C", repoPath, "status", "--short", "--branch"])
        case "diff":
            var cmd = ["git", "-C", repoPath, "diff"]
            if let path = arguments["path"]?.stringValue { cmd += ["--", path] }
            return run(cmd, maxChars: 12_000)
        case "log":
            let ref = arguments["ref"]?.stringValue ?? "HEAD"
            return run(["git", "-C", repoPath, "log", ref, "--oneline", "-\(limit)"])
        case "blame":
            guard let path = arguments["path"]?.stringValue else {
                throw ToolError.missingRequiredParameter("path")
            }
            return run(["git", "-C", repoPath, "blame", "--", path], maxChars: 10_000)
        case "commit":
            guard let msg = arguments["message"]?.stringValue else {
                throw ToolError.missingRequiredParameter("message")
            }
            return run(["git", "-C", repoPath, "commit", "-m", msg])
        case "push":
            return run(["git", "-C", repoPath, "push"])
        case "checkout":
            guard let branch = arguments["branch"]?.stringValue else {
                throw ToolError.missingRequiredParameter("branch")
            }
            return run(["git", "-C", repoPath, "checkout", branch])
        case "stash":
            return run(["git", "-C", repoPath, "stash"])
        case "branch":
            var cmd = ["git", "-C", repoPath, "branch", "-v"]
            if let b = arguments["branch"]?.stringValue { cmd = ["git", "-C", repoPath, "branch", b] }
            return run(cmd)
        case "show":
            let ref = arguments["ref"]?.stringValue ?? "HEAD"
            return run(["git", "-C", repoPath, "show", "--stat", ref], maxChars: 12_000)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Helpers

    private func run(_ args: [String], maxChars: Int = 8_000) -> ToolResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        try? p.run(); p.waitUntilExit()
        var output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if output.count > maxChars { output = String(output.prefix(maxChars)) + "\n... [truncated]" }
        return ToolResult(toolName: name, success: p.terminationStatus == 0, output: output)
    }

    private func resolvedRepoPath(_ raw: String?) -> String {
        guard let raw else { return NSHomeDirectory() }
        if raw.hasPrefix("~") { return NSString(string: raw).expandingTildeInPath }
        if raw.hasPrefix("/") { return raw }
        return NSHomeDirectory() + "/" + raw
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `/usr/bin/git` via `Process` | All Git operations |
| `ProcessInfo.processInfo.environment` | Inherit PATH, adding Homebrew paths |

### Key Implementation Steps

1. **repo_path** — resolve `~` and relative paths. Use `git -C <path>` so all commands work without `cd`.
2. **Read vs. write** — `status`, `diff`, `log`, `blame`, `show` are read-only. `commit`, `push`, `checkout`, `stash` modify repository state.
3. **Output truncation** — diff and blame can be very large; cap at `maxChars` (12,000 for diffs, 8,000 for others).
4. **Error passthrough** — Git's stderr is merged into stdout via the single pipe; the `terminationStatus` determines `success`.

### Output Truncation

Configurable per action: `diff` and `show` → 12,000 chars; others → 8,000 chars.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Access git repositories under `~` |
| `com.apple.security.files.user-selected.read-write` | Access repos outside home (user must grant via open panel) |

---

## Example Tool Calls

```json
{"tool": "git", "arguments": {"action": "status", "repo_path": "~/Projects/my-app"}}
```

```json
{"tool": "git", "arguments": {"action": "log", "repo_path": "~/Projects/my-app", "limit": 10}}
```

```json
{"tool": "git", "arguments": {"action": "commit", "repo_path": "~/Projects/my-app", "message": "Fix crash in ChatViewModel"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Not a git repository | Git returns `"fatal: not a git repository"` in output, `success: false` |
| Merge conflict during checkout | Git returns conflict message, `success: false` |
| Push rejected (upstream changes) | Git stderr explains; `success: false` |

---

## Edge Cases

- **Detached HEAD** — `git -C <path> status` works normally; `checkout <branch>` is safe.
- **Large binary diffs** — truncate at `maxChars` and note the file is binary if `git diff` says so.
- **Authentication for push** — SSH keys or credential helper must be pre-configured; this tool does not handle interactive authentication prompts.

---

## See Also

- [XcodeTool](./XcodeTool.md)
- [DiffTool](./DiffTool.md)
- [GitHubTool](./GitHubTool.md)
