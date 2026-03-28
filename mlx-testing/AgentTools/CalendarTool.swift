import EventKit
import Foundation

// MARK: - Calendar Tool

/// Lets the LLM interact with Apple Calendar — list calendars, query events,
/// create new events, update existing events, and delete events.
struct CalendarTool: AgentTool {

    let name = "calendar"

    let toolDescription = """
        Interact with Apple Calendar to manage events and calendars. \
        Can list calendars, query upcoming events, create new events with title/time/location/notes, \
        delete events by ID or title, search events by keyword, and update existing events. \
        Dates must be in ISO 8601 format (e.g. 2025-06-15T09:00:00).
        """

    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: .string,
            description: "The operation to perform",
            required: true,
            enumValues: ["list_calendars", "list_events", "create_event", "delete_event", "update_event", "search_events"]
        ),
        ToolParameter(
            name: "calendar_name",
            type: .string,
            description: "Calendar name to filter by or use when creating events (optional)",
            required: false
        ),
        ToolParameter(
            name: "start_date",
            type: .string,
            description: "Start date/time in ISO 8601 format (e.g. 2025-06-15T09:00:00). Required for create_event; optional filter for list_events and search_events.",
            required: false
        ),
        ToolParameter(
            name: "end_date",
            type: .string,
            description: "End date/time in ISO 8601 format. Required for create_event (event end time); optional upper bound for list_events.",
            required: false
        ),
        ToolParameter(
            name: "title",
            type: .string,
            description: "Event title. Required for create_event; used as search term for delete_event and search_events.",
            required: false
        ),
        ToolParameter(
            name: "notes",
            type: .string,
            description: "Event notes or description (for create_event and update_event)",
            required: false
        ),
        ToolParameter(
            name: "location",
            type: .string,
            description: "Event location (for create_event and update_event)",
            required: false
        ),
        ToolParameter(
            name: "event_id",
            type: .string,
            description: "Event identifier returned by list_events or search_events. Used for delete_event and update_event.",
            required: false
        ),
        ToolParameter(
            name: "query",
            type: .string,
            description: "Text to search for in event titles and notes (for search_events)",
            required: false
        ),
    ]

    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    // MARK: - Execute

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }

        let store = EKEventStore()
        let granted = try await requestAccess(store: store)
        guard granted else {
            return ToolResult(
                toolName: name,
                success: false,
                output: "Calendar access was denied. Grant access in System Settings → Privacy & Security → Calendars."
            )
        }

        switch action {
        case "list_calendars":
            return listCalendars(store: store)
        case "list_events":
            return listEvents(store: store, arguments: arguments)
        case "create_event":
            return try createEvent(store: store, arguments: arguments)
        case "delete_event":
            return try deleteEvent(store: store, arguments: arguments)
        case "update_event":
            return try updateEvent(store: store, arguments: arguments)
        case "search_events":
            return searchEvents(store: store, arguments: arguments)
        default:
            throw ToolError.executionFailed(
                "Unknown action: \(action). Use: list_calendars, list_events, create_event, delete_event, update_event, search_events"
            )
        }
    }

    // MARK: - Authorization

    private func requestAccess(store: EKEventStore) async throws -> Bool {
        return try await store.requestFullAccessToEvents()
    }

    // MARK: - List Calendars

    private func listCalendars(store: EKEventStore) -> ToolResult {
        let calendars = store.calendars(for: .event)
        guard !calendars.isEmpty else {
            return ToolResult(toolName: name, success: true, output: "No calendars found.")
        }

        let lines = calendars.map { cal -> String in
            let writeable = cal.allowsContentModifications ? "✎" : "🔒"
            return "\(writeable) \(cal.title) [\(cal.source.title)]"
        }
        return ToolResult(
            toolName: name,
            success: true,
            output: "Calendars (\(calendars.count)):\n" + lines.joined(separator: "\n")
        )
    }

    // MARK: - List Events

    private func listEvents(store: EKEventStore, arguments: [String: ToolArgumentValue]) -> ToolResult {
        let start = dateArg("start_date", from: arguments) ?? Date()
        let end = dateArg("end_date", from: arguments)
            ?? Calendar.current.date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 24 * 3600)

        let calendarFilter = calendarsMatching(name: arguments["calendar_name"]?.stringValue, store: store)
        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendarFilter.isEmpty ? nil : calendarFilter
        )
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        guard !events.isEmpty else {
            return ToolResult(
                toolName: name,
                success: true,
                output: "No events found between \(formatDate(start)) and \(formatDate(end))."
            )
        }

        // Keep output concise so the model can process it without choking
        let maxEvents = 15
        let truncated = events.count > maxEvents
        let lines = events.prefix(maxEvents).map { event -> String in
            var line = "• \(event.title ?? "(no title)")"
            line += "  —  \(formatDate(event.startDate)) → \(formatDate(event.endDate))"
            if let location = event.location, !location.isEmpty {
                line += "  📍 \(location)"
            }
            line += "  [\(event.calendar?.title ?? "?")]"
            return line
        }

        var output = "Events (\(events.count)\(truncated ? ", showing first \(maxEvents)" : ""))"
        output += " from \(formatDate(start)) to \(formatDate(end)):\n"
        output += lines.joined(separator: "\n")
        if truncated {
            output += "\n… and \(events.count - maxEvents) more events."
        }
        return ToolResult(toolName: name, success: true, output: output)
    }

    // MARK: - Create Event

    private func createEvent(store: EKEventStore, arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let title = arguments["title"]?.stringValue else {
            throw ToolError.missingRequiredParameter("title")
        }
        guard let startStr = arguments["start_date"]?.stringValue, let startDate = parseDate(startStr) else {
            throw ToolError.missingRequiredParameter("start_date")
        }
        guard let endStr = arguments["end_date"]?.stringValue, let endDate = parseDate(endStr) else {
            throw ToolError.missingRequiredParameter("end_date")
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate

        if let notes = arguments["notes"]?.stringValue { event.notes = notes }
        if let location = arguments["location"]?.stringValue { event.location = location }

        let matchedCalendars = calendarsMatching(name: arguments["calendar_name"]?.stringValue, store: store)
        event.calendar = matchedCalendars.first ?? store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent)
            return ToolResult(
                toolName: name,
                success: true,
                output: "Created event '\(title)' on \(formatDate(startDate)) (ID: \(event.eventIdentifier ?? "unknown"))"
            )
        } catch {
            return ToolResult(
                toolName: name,
                success: false,
                output: "Failed to create event: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Delete Event

    private func deleteEvent(store: EKEventStore, arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        // Prefer deletion by event_id when provided
        if let eventId = arguments["event_id"]?.stringValue,
           let event = store.event(withIdentifier: eventId) {
            let title = event.title ?? "(no title)"
            do {
                try store.remove(event, span: .thisEvent)
                return ToolResult(toolName: name, success: true, output: "Deleted event '\(title)'.")
            } catch {
                return ToolResult(
                    toolName: name,
                    success: false,
                    output: "Failed to delete event: \(error.localizedDescription)"
                )
            }
        }

        // Fallback: search by title within ±90 days
        guard let titleQuery = arguments["title"]?.stringValue else {
            throw ToolError.missingRequiredParameter("event_id or title")
        }

        let now = Date()
        let past = Calendar.current.date(byAdding: .day, value: -90, to: now)
            ?? now.addingTimeInterval(-90 * 24 * 3600)
        let future = Calendar.current.date(byAdding: .day, value: 90, to: now)
            ?? now.addingTimeInterval(90 * 24 * 3600)
        let predicate = store.predicateForEvents(withStart: past, end: future, calendars: nil)
        let matches = store.events(matching: predicate)
            .filter { ($0.title ?? "").localizedCaseInsensitiveContains(titleQuery) }

        if matches.isEmpty {
            return ToolResult(
                toolName: name,
                success: false,
                output: "No event found matching '\(titleQuery)'."
            )
        }

        if matches.count > 1 {
            let descriptions = matches.prefix(10).map {
                "• [\($0.eventIdentifier ?? "?")] \($0.title ?? "") on \(formatDate($0.startDate))"
            }
            return ToolResult(
                toolName: name,
                success: false,
                output: "Multiple events match '\(titleQuery)'. Provide an event_id:\n" + descriptions.joined(separator: "\n")
            )
        }

        let event = matches[0]
        let title = event.title ?? "(no title)"
        do {
            try store.remove(event, span: .thisEvent)
            return ToolResult(toolName: name, success: true, output: "Deleted event '\(title)'.")
        } catch {
            return ToolResult(
                toolName: name,
                success: false,
                output: "Failed to delete event: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Update Event

    private func updateEvent(store: EKEventStore, arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let eventId = arguments["event_id"]?.stringValue else {
            throw ToolError.missingRequiredParameter("event_id")
        }
        guard let event = store.event(withIdentifier: eventId) else {
            return ToolResult(toolName: name, success: false, output: "Event not found with ID: \(eventId)")
        }

        var changes: [String] = []

        if let title = arguments["title"]?.stringValue {
            event.title = title
            changes.append("title → '\(title)'")
        }
        if let startStr = arguments["start_date"]?.stringValue, let startDate = parseDate(startStr) {
            event.startDate = startDate
            changes.append("start → \(formatDate(startDate))")
        }
        if let endStr = arguments["end_date"]?.stringValue, let endDate = parseDate(endStr) {
            event.endDate = endDate
            changes.append("end → \(formatDate(endDate))")
        }
        if let notes = arguments["notes"]?.stringValue {
            event.notes = notes
            changes.append("notes updated")
        }
        if let location = arguments["location"]?.stringValue {
            event.location = location
            changes.append("location → '\(location)'")
        }

        if changes.isEmpty {
            return ToolResult(
                toolName: name,
                success: false,
                output: "No fields to update. Provide title, start_date, end_date, notes, or location."
            )
        }

        do {
            try store.save(event, span: .thisEvent)
            return ToolResult(
                toolName: name,
                success: true,
                output: "Updated '\(event.title ?? eventId)': \(changes.joined(separator: ", "))"
            )
        } catch {
            return ToolResult(
                toolName: name,
                success: false,
                output: "Failed to update event: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Search Events

    private func searchEvents(store: EKEventStore, arguments: [String: ToolArgumentValue]) -> ToolResult {
        let query = arguments["query"]?.stringValue ?? arguments["title"]?.stringValue ?? ""
        let now = Date()
        let start = dateArg("start_date", from: arguments)
            ?? Calendar.current.date(byAdding: .month, value: -1, to: now)
            ?? now.addingTimeInterval(-30 * 24 * 3600)
        let end = dateArg("end_date", from: arguments)
            ?? Calendar.current.date(byAdding: .month, value: 3, to: now)
            ?? now.addingTimeInterval(90 * 24 * 3600)

        let calendarFilter = calendarsMatching(name: arguments["calendar_name"]?.stringValue, store: store)
        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendarFilter.isEmpty ? nil : calendarFilter
        )
        let all = store.events(matching: predicate)

        let matches: [EKEvent]
        if query.isEmpty {
            matches = Array(all.sorted { $0.startDate < $1.startDate }.prefix(50))
        } else {
            matches = all
                .filter { event in
                    let titleMatch = (event.title ?? "").localizedCaseInsensitiveContains(query)
                    let notesMatch = (event.notes ?? "").localizedCaseInsensitiveContains(query)
                    return titleMatch || notesMatch
                }
                .sorted { $0.startDate < $1.startDate }
        }

        guard !matches.isEmpty else {
            let queryDescription = query.isEmpty ? "the given range" : "'\(query)'"
            return ToolResult(
                toolName: name,
                success: true,
                output: "No events found matching \(queryDescription)."
            )
        }

        let lines = matches.prefix(30).map { event -> String in
            "• [\(event.eventIdentifier ?? "?")] \(event.title ?? "(no title)") — \(formatDate(event.startDate))"
        }
        let queryDescription = query.isEmpty ? "the given range" : "'\(query)'"
        return ToolResult(
            toolName: name,
            success: true,
            output: "Found \(matches.count) event(s) matching \(queryDescription):\n" + lines.joined(separator: "\n")
        )
    }

    // MARK: - Helpers

    /// Safely extract a date from an optional argument value.
    private func dateArg(_ key: String, from arguments: [String: ToolArgumentValue]) -> Date? {
        guard let value = arguments[key]?.stringValue else { return nil }
        return parseDate(value)
    }

    /// Parse an ISO 8601 date string (with or without time component) or "yyyy-MM-dd HH:mm" format.
    private func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        if let d = iso.date(from: string) { return d }

        iso.formatOptions = [.withFullDate]
        if let d = iso.date(from: string) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        if let d = df.date(from: string) { return d }

        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: string)
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private func calendarsMatching(name: String?, store: EKEventStore) -> [EKCalendar] {
        guard let name = name, !name.isEmpty else { return [] }
        return store.calendars(for: .event).filter { $0.title.localizedCaseInsensitiveContains(name) }
    }
}
