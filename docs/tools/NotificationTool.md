# NotificationTool

**Category:** macOS System & Hardware
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `notification`

## Overview

`NotificationTool` delivers and schedules macOS user notifications via the `UserNotifications` framework. The LLM can use it to alert the user when a long-running background task completes, send a reminder at a specified time, or list pending scheduled notifications. Because notifications are passive (they don't modify system state beyond posting an alert), this tool has a low risk level and does not require per-invocation approval.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `post`, `schedule`, `list`, `cancel` |
| `title` | string | No | `"MLX Copilot"` | Notification title |
| `body` | string | No | — | Notification body text (required for `post` and `schedule`) |
| `subtitle` | string | No | — | Optional subtitle |
| `identifier` | string | No | auto-UUID | Unique ID for the notification (used to cancel) |
| `delay_seconds` | integer | No | — | Seconds from now to deliver the notification (for `schedule`) |
| `datetime` | string | No | — | ISO-8601 datetime string for `schedule` (alternative to `delay_seconds`) |

---

## Swift Implementation

```swift
import Foundation
import UserNotifications

struct NotificationTool: AgentTool {

    let name = "notification"
    let toolDescription = "Post immediate or scheduled macOS notifications. List and cancel pending notifications."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",   type: .string, description: "post | schedule | list | cancel",
                      required: true, enumValues: ["post", "schedule", "list", "cancel"]),
        ToolParameter(name: "title",    type: .string,  description: "Notification title",           required: false, defaultValue: "MLX Copilot"),
        ToolParameter(name: "body",     type: .string,  description: "Notification body",            required: false),
        ToolParameter(name: "subtitle", type: .string,  description: "Optional subtitle",            required: false),
        ToolParameter(name: "identifier",     type: .string,  description: "Unique notification ID", required: false),
        ToolParameter(name: "delay_seconds",  type: .integer, description: "Seconds until delivery", required: false),
        ToolParameter(name: "datetime",       type: .string,  description: "ISO-8601 datetime",      required: false),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        // Request permission if not yet granted
        try await requestPermissionIfNeeded()

        switch action {
        case "post":     return try await postNotification(arguments: arguments)
        case "schedule": return try await scheduleNotification(arguments: arguments)
        case "list":     return await listPending()
        case "cancel":   return try cancelNotification(arguments: arguments)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func postNotification(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let body = arguments["body"]?.stringValue else {
            throw ToolError.missingRequiredParameter("body")
        }
        let content = makeContent(arguments: arguments, body: body)
        let trigger: UNNotificationTrigger? = nil  // immediate
        let id = arguments["identifier"]?.stringValue ?? UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
        return ToolResult(toolName: name, success: true, output: "Notification posted (id: \(id))")
    }

    private func scheduleNotification(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let body = arguments["body"]?.stringValue else {
            throw ToolError.missingRequiredParameter("body")
        }
        let content = makeContent(arguments: arguments, body: body)
        let id = arguments["identifier"]?.stringValue ?? UUID().uuidString

        let trigger: UNNotificationTrigger
        if case .integer(let delay) = arguments["delay_seconds"] {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(delay), repeats: false)
        } else if let isoString = arguments["datetime"]?.stringValue,
                  let date = ISO8601DateFormatter().date(from: isoString) {
            let components = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            throw ToolError.missingRequiredParameter("delay_seconds or datetime")
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
        return ToolResult(toolName: name, success: true, output: "Notification scheduled (id: \(id))")
    }

    private func listPending() async -> ToolResult {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        if pending.isEmpty {
            return ToolResult(toolName: name, success: true, output: "No pending notifications.")
        }
        let lines = pending.map { r -> String in
            let triggerDesc: String
            if let t = r.trigger as? UNTimeIntervalNotificationTrigger {
                triggerDesc = "in \(Int(t.timeInterval))s"
            } else if let t = r.trigger as? UNCalendarNotificationTrigger {
                triggerDesc = "\(t.dateComponents)"
            } else {
                triggerDesc = "immediate"
            }
            return "  [\(r.identifier)] \(r.content.title): \(r.content.body) — \(triggerDesc)"
        }
        return ToolResult(toolName: name, success: true,
                          output: "Pending notifications (\(pending.count)):\n" + lines.joined(separator: "\n"))
    }

    private func cancelNotification(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let id = arguments["identifier"]?.stringValue else {
            throw ToolError.missingRequiredParameter("identifier")
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        return ToolResult(toolName: name, success: true, output: "Cancelled notification: \(id)")
    }

    // MARK: - Helpers

    private func makeContent(arguments: [String: ToolArgumentValue], body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title    = arguments["title"]?.stringValue ?? "MLX Copilot"
        content.body     = body
        if let sub = arguments["subtitle"]?.stringValue { content.subtitle = sub }
        content.sound    = .default
        return content
    }

    private func requestPermissionIfNeeded() async throws {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `UserNotifications` — `UNUserNotificationCenter` | All notification delivery and management |
| `UNTimeIntervalNotificationTrigger` | Schedule relative to "now" by seconds |
| `UNCalendarNotificationTrigger` | Schedule at an absolute date/time via `DateComponents` |

### Key Implementation Steps

1. **Permission** — on first invocation, call `requestAuthorization(options: [.alert, .sound])` and await the result. If denied, return a message directing the user to System Settings > Notifications.
2. **Post** — build a `UNMutableNotificationContent`, set `title`/`body`/`subtitle`/`sound`, create a `UNNotificationRequest` with `trigger = nil` for immediate delivery.
3. **Schedule** — use `UNTimeIntervalNotificationTrigger` for relative delays and `UNCalendarNotificationTrigger` for absolute datetime. Parse the `datetime` parameter with `ISO8601DateFormatter`.
4. **List** — `UNUserNotificationCenter.current().pendingNotificationRequests()` returns all scheduled requests. Format each with its identifier and trigger description.
5. **Cancel** — `removePendingNotificationRequests(withIdentifiers:)`.

---

## Sandbox Entitlements

No additional entitlements required. `UserNotifications` is available to all sandboxed macOS apps.

---

## Example Tool Calls

```json
{"tool": "notification", "arguments": {"action": "post", "title": "Done!", "body": "Your export has finished."}}
```

```json
{"tool": "notification", "arguments": {"action": "schedule", "body": "Stand up!", "delay_seconds": 3600}}
```

```json
{"tool": "notification", "arguments": {"action": "list"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| User denied notification permission | Returns `"Notification permission denied. Enable in System Settings > Notifications."` |
| `body` missing for `post` / `schedule` | Throws `ToolError.missingRequiredParameter("body")` |
| Neither `delay_seconds` nor `datetime` for `schedule` | Throws `ToolError.missingRequiredParameter("delay_seconds or datetime")` |
| Past `datetime` provided | `UNCalendarNotificationTrigger` will not fire; return a warning |

---

## Edge Cases

- **Focus modes** — the notification may be suppressed if the user has Do Not Disturb active. There is no API to override Focus filters from a third-party app.
- **App in background** — `UNUserNotificationCenter` delivers notifications regardless of app state.
- **Identifier reuse** — posting with an existing identifier replaces the previous notification.

---

## See Also

- [RemindersTool](./RemindersTool.md)
- [CountdownTimerTool](./CountdownTimerTool.md)
