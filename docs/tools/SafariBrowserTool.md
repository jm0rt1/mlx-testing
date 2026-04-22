# SafariBrowserTool

**Category:** Productivity & Personal Data
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `safari`

## Overview

`SafariBrowserTool` controls Safari via AppleScript. Reading the current tab URL/title is low risk. Opening new tabs, executing JavaScript, or navigating modifies browser state and requires approval.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `current_tab`, `open_url`, `list_tabs`, `get_source`, `run_js` |
| `url` | string | No | — | URL to open (for `open_url`) |
| `javascript` | string | No | — | JS snippet to evaluate (for `run_js`) |

---

## Swift Implementation

```swift
import Foundation

struct SafariBrowserTool: AgentTool {

    let name = "safari"
    let toolDescription = "Control Safari: get active tab URL/title, open URLs, list all tabs, get page HTML source, run JavaScript."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",     type: .string, description: "current_tab | open_url | list_tabs | get_source | run_js",
                      required: true, enumValues: ["current_tab", "open_url", "list_tabs", "get_source", "run_js"]),
        ToolParameter(name: "url",        type: .string, description: "URL to open",              required: false),
        ToolParameter(name: "javascript", type: .string, description: "JavaScript to evaluate",   required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }

        switch action {
        case "current_tab":
            return runAppleScript("""
                tell application "Safari"
                    set t to current tab of front window
                    return URL of t & "\\n" & name of t
                end tell
                """)
        case "open_url":
            guard let url = arguments["url"]?.stringValue else { throw ToolError.missingRequiredParameter("url") }
            return runAppleScript("tell application \"Safari\" to open location \"\(url)\"")
        case "list_tabs":
            return runAppleScript("""
                tell application "Safari"
                    set result to ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set result to result & (URL of t) & " | " & (name of t) & "\\n"
                        end repeat
                    end repeat
                    result
                end tell
                """, maxChars: 5_000)
        case "get_source":
            return runAppleScript("""
                tell application "Safari"
                    source of document 1
                end tell
                """, maxChars: 10_000)
        case "run_js":
            guard let js = arguments["javascript"]?.stringValue else { throw ToolError.missingRequiredParameter("javascript") }
            return runAppleScript("""
                tell application "Safari"
                    do JavaScript "\(js.replacingOccurrences(of: "\"", with: "\\\""))" in current tab of front window
                end tell
                """)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    private func runAppleScript(_ script: String, maxChars: Int = 3_000) -> ToolResult {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)
        if let err = error { return ToolResult(toolName: name, success: false, output: "AppleScript error: \(err)") }
        var text = result?.stringValue ?? "(no output)"
        if text.count > maxChars { text = String(text.prefix(maxChars)) + "\n... [truncated]" }
        return ToolResult(toolName: name, success: true, output: text)
    }
}
```

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.automation.apple-events` | AppleScript to Safari (already present) |

---

## Example Tool Calls

```json
{"tool": "safari", "arguments": {"action": "current_tab"}}
```

```json
{"tool": "safari", "arguments": {"action": "open_url", "url": "https://swift.org"}}
```

---

## See Also

- [WebScraperTool](./WebScraperTool.md)
- [AppleScriptTool](./AppleScriptTool.md)
