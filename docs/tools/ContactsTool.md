# ContactsTool

**Category:** Productivity & Personal Data
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `contacts`

## Overview

`ContactsTool` searches the user's contacts via `CNContactStore`. It is read-only (no contact modification), returning names, email addresses, phone numbers, and company information. Safe for automatic use.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `search`, `list_groups` |
| `query` | string | No | — | Name, email, or phone number to search |
| `group` | string | No | — | Contact group name to list (for `list_groups`) |
| `max_results` | integer | No | `20` | Maximum contacts to return |

---

## Swift Implementation

```swift
import Foundation
import Contacts

struct ContactsTool: AgentTool {

    let name = "contacts"
    let toolDescription = "Search contacts by name, email, or phone number. Read-only access via CNContactStore."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",      type: .string,  description: "search | list_groups",
                      required: true, enumValues: ["search", "list_groups"]),
        ToolParameter(name: "query",       type: .string,  description: "Name, email, or phone",    required: false),
        ToolParameter(name: "group",       type: .string,  description: "Group name filter",        required: false),
        ToolParameter(name: "max_results", type: .integer, description: "Max results (default 20)", required: false, defaultValue: "20"),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    private let store = CNContactStore()
    private let keysToFetch: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
    ]

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }

        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .denied || status == .restricted {
            return ToolResult(toolName: name, success: false,
                              output: "Contacts access denied. Enable in System Settings > Privacy & Security > Contacts.")
        }
        if status == .notDetermined {
            try await store.requestAccess(for: .contacts)
        }

        let maxResults: Int
        if case .integer(let m) = arguments["max_results"] { maxResults = min(m, 100) } else { maxResults = 20 }

        switch action {
        case "search":
            let query = arguments["query"]?.stringValue ?? ""
            return try searchContacts(query: query, maxResults: maxResults)
        case "list_groups":
            return try listGroups(groupName: arguments["group"]?.stringValue, maxResults: maxResults)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func searchContacts(query: String, maxResults: Int) throws -> ToolResult {
        let predicate: NSPredicate
        if query.isEmpty {
            predicate = CNContact.predicateForContactsInContainer(withIdentifier: store.defaultContainerIdentifier())
        } else if query.contains("@") {
            // Email search — CNContactStore doesn't have a direct email predicate; use name + filter
            predicate = CNContact.predicateForContacts(matchingName: query)
        } else {
            predicate = CNContact.predicateForContacts(matchingName: query)
        }

        var contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

        // Supplement with email/phone filter if needed
        if query.contains("@") || query.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" || $0 == " " }) {
            contacts = contacts.filter { c in
                c.emailAddresses.contains { ($0.value as String).localizedCaseInsensitiveContains(query) } ||
                c.phoneNumbers.contains { $0.value.stringValue.contains(query) }
            }
        }

        let limited = Array(contacts.prefix(maxResults))
        let lines = limited.map { c -> String in
            let name    = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
            let emails  = c.emailAddresses.map { $0.value as String }.joined(separator: ", ")
            let phones  = c.phoneNumbers.map { $0.value.stringValue }.joined(separator: ", ")
            let company = c.organizationName
            var parts = [name.isEmpty ? "Unknown" : name]
            if !emails.isEmpty  { parts.append("✉ \(emails)") }
            if !phones.isEmpty  { parts.append("☎ \(phones)") }
            if !company.isEmpty { parts.append("🏢 \(company)") }
            return parts.joined(separator: "  ")
        }
        return ToolResult(toolName: name, success: true,
                          output: "Contacts (\(limited.count) of \(contacts.count)):\n" + (lines.isEmpty ? "(none)" : lines.joined(separator: "\n")))
    }

    private func listGroups(groupName: String?, maxResults: Int) throws -> ToolResult {
        let groups = try store.groups(matching: nil)
        let filtered = groupName.map { g in groups.filter { $0.name.localizedCaseInsensitiveContains(g) } } ?? groups
        let lines = filtered.map { "  • \($0.name) (id: \($0.identifier))" }
        return ToolResult(toolName: name, success: true,
                          output: "Contact groups (\(filtered.count)):\n" + lines.joined(separator: "\n"))
    }
}
```

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.personal-information.addressbook` | CNContactStore access |

---

## Example Tool Calls

```json
{"tool": "contacts", "arguments": {"action": "search", "query": "John Smith"}}
```

```json
{"tool": "contacts", "arguments": {"action": "search", "query": "john@example.com"}}
```

---

## See Also

- [MailTool](./MailTool.md)
- [CalendarTool](./CalendarTool.md)
