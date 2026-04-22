# RemindersTool

**Category:** Productivity & Personal Data
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `reminders`

## Overview

`RemindersTool` manages reminders via the `EventKit` framework. Listing is read-only; creating, completing, and deleting reminders modify the Reminders database and require approval.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list`, `create`, `complete`, `delete`, `search` |
| `list_name` | string | No | — | Reminders list name filter |
| `title` | string | No | — | Reminder title (for `create`, `search`) |
| `due_date` | string | No | — | ISO-8601 due date (for `create`) |
| `priority` | integer | No | `0` | Priority 0–9 (0=none, 1=high, 5=medium, 9=low) |
| `reminder_id` | string | No | — | Reminder identifier (for `complete`, `delete`) |

---

## Swift Implementation

```swift
import Foundation
import EventKit

struct RemindersTool: AgentTool {

    let name = "reminders"
    let toolDescription = "Manage Apple Reminders: list, create, complete, and delete reminders via EventKit."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",      type: .string, description: "list | create | complete | delete | search",
                      required: true, enumValues: ["list", "create", "complete", "delete", "search"]),
        ToolParameter(name: "list_name",   type: .string,  description: "Reminders list name filter", required: false),
        ToolParameter(name: "title",       type: .string,  description: "Reminder title",             required: false),
        ToolParameter(name: "due_date",    type: .string,  description: "ISO-8601 due date",          required: false),
        ToolParameter(name: "priority",    type: .integer, description: "0-9 (0=none, 1=high)",       required: false, defaultValue: "0"),
        ToolParameter(name: "reminder_id", type: .string,  description: "Reminder identifier",        required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    private let store = EKEventStore()
    private let iso   = ISO8601DateFormatter()

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }

        let granted = try await store.requestFullAccessToReminders()
        guard granted else {
            return ToolResult(toolName: name, success: false,
                              output: "Reminders access denied. Enable in System Settings > Privacy & Security > Reminders.")
        }

        switch action {
        case "list":     return await listReminders(arguments: arguments)
        case "create":   return try createReminder(arguments: arguments)
        case "complete": return try completeReminder(arguments: arguments)
        case "delete":   return try deleteReminder(arguments: arguments)
        case "search":   return await searchReminders(keyword: arguments["title"]?.stringValue ?? "")
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func listReminders(arguments: [String: ToolArgumentValue]) async -> ToolResult {
        let lists = filterLists(by: arguments["list_name"]?.stringValue)
        let pred  = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }

        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
        let lines = reminders.map { r in
            let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map { df.string(from: $0) } ?? "no due date"
            return "  [\(r.calendar.title)] \(r.title ?? "?") — due: \(due) (id: \(r.calendarItemIdentifier))"
        }
        return ToolResult(toolName: name, success: true,
                          output: "Incomplete reminders (\(reminders.count)):\n" + (lines.isEmpty ? "(none)" : lines.joined(separator: "\n")))
    }

    private func createReminder(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let title = arguments["title"]?.stringValue else { throw ToolError.missingRequiredParameter("title") }
        let reminder = EKReminder(eventStore: store)
        reminder.title    = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let dateStr = arguments["due_date"]?.stringValue, let date = iso.date(from: dateStr) {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }
        if case .integer(let p) = arguments["priority"] { reminder.priority = p }
        try store.save(reminder, commit: true)
        return ToolResult(toolName: name, success: true, output: "Created reminder '\(title)' (id: \(reminder.calendarItemIdentifier))")
    }

    private func completeReminder(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let id = arguments["reminder_id"]?.stringValue else { throw ToolError.missingRequiredParameter("reminder_id") }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            return ToolResult(toolName: name, success: false, output: "Reminder not found: \(id)")
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
        return ToolResult(toolName: name, success: true, output: "Marked as completed: \(reminder.title ?? id)")
    }

    private func deleteReminder(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let id = arguments["reminder_id"]?.stringValue else { throw ToolError.missingRequiredParameter("reminder_id") }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            return ToolResult(toolName: name, success: false, output: "Reminder not found: \(id)")
        }
        let title = reminder.title ?? id
        try store.remove(reminder, commit: true)
        return ToolResult(toolName: name, success: true, output: "Deleted reminder: \(title)")
    }

    private func searchReminders(keyword: String) async -> ToolResult {
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let all: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
        let filtered = all.filter { ($0.title ?? "").localizedCaseInsensitiveContains(keyword) }
        let lines = filtered.map { "  \($0.title ?? "?") (id: \($0.calendarItemIdentifier))" }
        return ToolResult(toolName: name, success: true,
                          output: "Found \(filtered.count) reminder(s) matching '\(keyword)':\n" + lines.joined(separator: "\n"))
    }

    private func filterLists(by name: String?) -> [EKCalendar]? {
        guard let name else { return nil }
        return store.calendars(for: .reminder).filter { $0.title.localizedCaseInsensitiveContains(name) }
    }
}
```

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.personal-information.reminders` | EventKit reminders access |

---

## Example Tool Calls

```json
{"tool": "reminders", "arguments": {"action": "list"}}
```

```json
{"tool": "reminders", "arguments": {"action": "create", "title": "Buy groceries", "due_date": "2025-01-15T18:00:00Z"}}
```

---

## See Also

- [CalendarTool](./CalendarTool.md)
- [NotificationTool](./NotificationTool.md)
