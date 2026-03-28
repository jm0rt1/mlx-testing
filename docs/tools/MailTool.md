# MailTool

**Category:** Productivity & Personal Data
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `mail`

## Overview

`MailTool` interacts with Mail.app via AppleScript. Listing and reading messages is low risk; composing drafts requires approval. This tool never sends mail without explicit user confirmation — it only creates drafts. Useful for summarising unread messages, generating email replies, or drafting notifications.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `unread_count`, `list_unread`, `search`, `create_draft` |
| `mailbox` | string | No | `"Inbox"` | Mailbox name (for `unread_count`, `list_unread`) |
| `query` | string | No | — | Search query (for `search`) |
| `to` | string | No | — | Recipient email (for `create_draft`) |
| `subject` | string | No | — | Subject line (for `create_draft`) |
| `body` | string | No | — | Email body (for `create_draft`) |
| `max_results` | integer | No | `10` | Max messages to list |

---

## Swift Implementation

```swift
import Foundation

struct MailTool: AgentTool {

    let name = "mail"
    let toolDescription = "Interact with Mail.app via AppleScript: count unread, list messages, search, and create drafts."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",      type: .string, description: "unread_count | list_unread | search | create_draft",
                      required: true, enumValues: ["unread_count", "list_unread", "search", "create_draft"]),
        ToolParameter(name: "mailbox",     type: .string,  description: "Mailbox name",              required: false, defaultValue: "Inbox"),
        ToolParameter(name: "query",       type: .string,  description: "Search query",              required: false),
        ToolParameter(name: "to",          type: .string,  description: "Recipient email",           required: false),
        ToolParameter(name: "subject",     type: .string,  description: "Subject line",              required: false),
        ToolParameter(name: "body",        type: .string,  description: "Email body",                required: false),
        ToolParameter(name: "max_results", type: .integer, description: "Max messages",              required: false, defaultValue: "10"),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }
        let mailbox = arguments["mailbox"]?.stringValue ?? "Inbox"
        let maxResults: Int
        if case .integer(let m) = arguments["max_results"] { maxResults = min(m, 50) } else { maxResults = 10 }

        switch action {
        case "unread_count":
            return runAppleScript("tell application \"Mail\"\ncount (messages of mailbox \"\(mailbox)\" whose read status is false)\nend tell")
        case "list_unread":
            let script = """
            tell application "Mail"
                set msgs to (messages of mailbox "\(mailbox)" whose read status is false)
                set result to ""
                repeat with i from 1 to (count of msgs)
                    if i > \(maxResults) then exit repeat
                    set m to item i of msgs
                    set result to result & (subject of m) & " | " & (sender of m) & " | " & ((date received of m) as string) & "\\n"
                end repeat
                result
            end tell
            """
            return runAppleScript(script)
        case "search":
            guard let q = arguments["query"]?.stringValue else { throw ToolError.missingRequiredParameter("query") }
            let script = """
            tell application "Mail"
                set msgs to (messages of mailbox "\(mailbox)" whose subject contains "\(q)" or sender contains "\(q)")
                set result to ""
                repeat with i from 1 to (count of msgs)
                    if i > \(maxResults) then exit repeat
                    set m to item i of msgs
                    set result to result & (subject of m) & " | " & (sender of m) & "\\n"
                end repeat
                result
            end tell
            """
            return runAppleScript(script)
        case "create_draft":
            guard let to      = arguments["to"]?.stringValue      else { throw ToolError.missingRequiredParameter("to") }
            guard let subject = arguments["subject"]?.stringValue else { throw ToolError.missingRequiredParameter("subject") }
            let body = arguments["body"]?.stringValue ?? ""
            let script = """
            tell application "Mail"
                set newMsg to make new outgoing message with properties {subject:"\(subject)", content:"\(body)", visible:true}
                tell newMsg
                    make new to recipient with properties {address:"\(to)"}
                end tell
            end tell
            """
            return runAppleScript(script)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Helper

    private func runAppleScript(_ script: String) -> ToolResult {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let output = appleScript?.executeAndReturnError(&error)
        if let err = error {
            return ToolResult(toolName: name, success: false, output: "AppleScript error: \(err)")
        }
        let text = output?.stringValue ?? "(no output)"
        return ToolResult(toolName: name, success: true, output: text)
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `NSAppleScript` | Drive Mail.app via AppleScript |

### Key Implementation Steps

1. **unread_count** — `count (messages of mailbox "Inbox" whose read status is false)`.
2. **list_unread** — iterate unread messages, extract subject, sender, and date. Cap at `maxResults`.
3. **search** — filter by subject or sender containing the query string.
4. **create_draft** — `make new outgoing message` with `visible: true` opens the compose window without sending.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.automation.apple-events` | AppleScript to Mail.app (already present) |

---

## Example Tool Calls

```json
{"tool": "mail", "arguments": {"action": "unread_count", "mailbox": "Inbox"}}
```

```json
{"tool": "mail", "arguments": {"action": "create_draft", "to": "alice@example.com", "subject": "Meeting follow-up", "body": "Hi Alice, ..."}}
```

---

## See Also

- [ContactsTool](./ContactsTool.md)
- [SlackTool](./SlackTool.md)
