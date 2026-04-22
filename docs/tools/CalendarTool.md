# CalendarTool

**Category:** Productivity & Personal Data
**Risk Level:** medium
**Requires Approval:** Yes (for create/update/delete)
**Tool Identifier:** `calendar`

## Overview

`CalendarTool` reads and writes calendar events via the `EventKit` framework. Listing events is read-only; creating, updating, or deleting events modifies the calendar database and requires approval. Useful for scheduling tasks, reviewing upcoming meetings, or automating recurring event creation.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list`, `create`, `update`, `delete`, `search` |
| `start_date` | string | No | today | ISO-8601 date for range start (for `list`) |
| `end_date` | string | No | +7 days | ISO-8601 date for range end (for `list`) |
| `calendar_name` | string | No | — | Filter by specific calendar name |
| `title` | string | No | — | Event title (for `create`, `update`, `search`) |
| `location` | string | No | — | Event location (for `create`) |
| `start` | string | No | — | ISO-8601 start datetime (for `create`) |
| `end` | string | No | — | ISO-8601 end datetime (for `create`) |
| `notes` | string | No | — | Event notes/description (for `create`, `update`) |
| `event_id` | string | No | — | Event identifier (for `update`, `delete`) |

---

## Swift Implementation

```swift
import Foundation
import EventKit

struct CalendarTool: AgentTool {

    let name = "calendar"
    let toolDescription = "Read and write calendar events via EventKit. List upcoming events, create, update, and delete events."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",        type: .string, description: "list | create | update | delete | search",
                      required: true, enumValues: ["list", "create", "update", "delete", "search"]),
        ToolParameter(name: "start_date",    type: .string,  description: "Range start (ISO-8601)",          required: false),
        ToolParameter(name: "end_date",      type: .string,  description: "Range end (ISO-8601)",            required: false),
        ToolParameter(name: "calendar_name", type: .string,  description: "Calendar name filter",           required: false),
        ToolParameter(name: "title",         type: .string,  description: "Event title",                    required: false),
        ToolParameter(name: "location",      type: .string,  description: "Location",                       required: false),
        ToolParameter(name: "start",         type: .string,  description: "Event start datetime (ISO-8601)",required: false),
        ToolParameter(name: "end",           type: .string,  description: "Event end datetime (ISO-8601)",  required: false),
        ToolParameter(name: "notes",         type: .string,  description: "Notes / description",            required: false),
        ToolParameter(name: "event_id",      type: .string,  description: "Event identifier",               required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    private let store = EKEventStore()
    private let iso   = ISO8601DateFormatter()

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }

        // Request access
        let granted = try await store.requestFullAccessToEvents()
        guard granted else {
            return ToolResult(toolName: name, success: false,
                              output: "Calendar access denied. Enable in System Settings > Privacy & Security > Calendars.")
        }

        switch action {
        case "list":   return listEvents(arguments: arguments)
        case "create": return try createEvent(arguments: arguments)
        case "update": return try updateEvent(arguments: arguments)
        case "delete": return try deleteEvent(arguments: arguments)
        case "search": return searchEvents(arguments: arguments)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func listEvents(arguments: [String: ToolArgumentValue]) -> ToolResult {
        let start = iso.date(from: arguments["start_date"]?.stringValue ?? "") ?? Date()
        let end   = iso.date(from: arguments["end_date"]?.stringValue ?? "")
                  ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())!

        let calendars = filterCalendars(by: arguments["calendar_name"]?.stringValue)
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: pred)

        let df = DateFormatter()
        df.dateStyle = .short; df.timeStyle = .short

        let lines = events.map { e in
            "\(df.string(from: e.startDate)) — \(e.title ?? "Untitled") [\(e.calendar.title)]"
        }
        return ToolResult(toolName: name, success: true,
                          output: "Events (\(events.count)):\n" + (lines.isEmpty ? "(none)" : lines.joined(separator: "\n")))
    }

    private func createEvent(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let title = arguments["title"]?.stringValue else { throw ToolError.missingRequiredParameter("title") }
        guard let startStr = arguments["start"]?.stringValue, let start = iso.date(from: startStr) else {
            throw ToolError.missingRequiredParameter("start")
        }
        let end = iso.date(from: arguments["end"]?.stringValue ?? "") ?? Calendar.current.date(byAdding: .hour, value: 1, to: start)!

        let event = EKEvent(eventStore: store)
        event.title    = title
        event.startDate = start
        event.endDate   = end
        if let loc   = arguments["location"]?.stringValue { event.location = loc }
        if let notes = arguments["notes"]?.stringValue    { event.notes    = notes }
        event.calendar = store.defaultCalendarForNewEvents

        try store.save(event, span: .thisEvent)
        return ToolResult(toolName: name, success: true, output: "Created event '\(title)' (id: \(event.eventIdentifier ?? "?"))")
    }

    private func updateEvent(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let eventId = arguments["event_id"]?.stringValue else { throw ToolError.missingRequiredParameter("event_id") }
        guard let event = store.event(withIdentifier: eventId) else {
            return ToolResult(toolName: name, success: false, output: "Event not found: \(eventId)")
        }
        if let title = arguments["title"]?.stringValue { event.title = title }
        if let notes = arguments["notes"]?.stringValue { event.notes = notes }
        if let startStr = arguments["start"]?.stringValue, let start = iso.date(from: startStr) { event.startDate = start }
        if let endStr   = arguments["end"]?.stringValue,   let end   = iso.date(from: endStr)   { event.endDate   = end }
        try store.save(event, span: .thisEvent)
        return ToolResult(toolName: name, success: true, output: "Updated event: \(event.title ?? eventId)")
    }

    private func deleteEvent(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let eventId = arguments["event_id"]?.stringValue else { throw ToolError.missingRequiredParameter("event_id") }
        guard let event = store.event(withIdentifier: eventId) else {
            return ToolResult(toolName: name, success: false, output: "Event not found: \(eventId)")
        }
        let title = event.title ?? eventId
        try store.remove(event, span: .thisEvent)
        return ToolResult(toolName: name, success: true, output: "Deleted event: \(title)")
    }

    private func searchEvents(arguments: [String: ToolArgumentValue]) -> ToolResult {
        guard let keyword = arguments["title"]?.stringValue else { return listEvents(arguments: arguments) }
        let start = Date()
        let end   = Calendar.current.date(byAdding: .year, value: 1, to: start)!
        let pred  = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let matching = store.events(matching: pred).filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(keyword)
        }
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
        let lines = matching.map { "\(df.string(from: $0.startDate)) — \($0.title ?? "?") (id: \($0.eventIdentifier ?? "?"))" }
        return ToolResult(toolName: name, success: true,
                          output: "Found \(matching.count) event(s) matching '\(keyword)':\n" + lines.joined(separator: "\n"))
    }

    // MARK: - Helper

    private func filterCalendars(by name: String?) -> [EKCalendar]? {
        guard let name else { return nil }
        return store.calendars(for: .event).filter { $0.title.localizedCaseInsensitiveContains(name) }
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `EventKit` — `EKEventStore`, `EKEvent` | Full calendar CRUD |
| `EKEventStore.requestFullAccessToEvents()` | macOS 14+ permission API |
| `EKEventStore.predicateForEvents(withStart:end:calendars:)` | Date-range event query |

### Key Implementation Steps

1. **Permission** — call `requestFullAccessToEvents()` on every invocation. If denied, return a descriptive message.
2. **List** — parse ISO-8601 dates for range, build a predicate, call `store.events(matching:)`.
3. **Create** — build an `EKEvent`, set required fields, assign `store.defaultCalendarForNewEvents`, call `store.save`.
4. **Update** — fetch by `eventIdentifier`, modify fields, save.
5. **Delete** — fetch by `eventIdentifier`, call `store.remove`.
6. **Search** — use a 1-year window predicate and filter by title keyword client-side.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.personal-information.calendars` | EventKit calendar access |

---

## Example Tool Calls

```json
{"tool": "calendar", "arguments": {"action": "list", "start_date": "2025-01-01", "end_date": "2025-01-07"}}
```

```json
{"tool": "calendar", "arguments": {"action": "create", "title": "Team standup", "start": "2025-01-15T09:00:00Z", "end": "2025-01-15T09:30:00Z"}}
```

---

## See Also

- [RemindersTool](./RemindersTool.md)
- [NotificationTool](./NotificationTool.md)
- [CalendarMeetingTool](./CalendarMeetingTool.md)
