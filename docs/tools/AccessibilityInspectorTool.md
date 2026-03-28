# AccessibilityInspectorTool

**Category:** macOS System & Hardware
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `accessibility_inspector`

## Overview

`AccessibilityInspectorTool` reads the macOS Accessibility tree of any running application using the `AXUIElement` API. It returns a structured list of UI elements with their roles, labels, and values. This is read-only and enables the LLM to understand what is currently displayed on screen, which is foundational for building higher-level automation without requiring a screenshot or VLM.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list_apps`, `inspect`, `read_focused` |
| `app_name` | string | No | — | Target application name (for `inspect`) |
| `depth` | integer | No | `3` | Recursion depth for tree traversal (1–6) |

---

## Swift Implementation

```swift
import Foundation
import ApplicationServices

struct AccessibilityInspectorTool: AgentTool {

    let name = "accessibility_inspector"
    let toolDescription = "Inspect the macOS Accessibility tree of running apps: list UI elements, roles, labels, and values."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",   type: .string, description: "list_apps | inspect | read_focused",
                      required: true, enumValues: ["list_apps", "inspect", "read_focused"]),
        ToolParameter(name: "app_name", type: .string,  description: "Application name to inspect", required: false),
        ToolParameter(name: "depth",    type: .integer, description: "Tree depth 1–6 (default 3)",  required: false, defaultValue: "3"),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard AXIsProcessTrusted() else {
            return ToolResult(toolName: name, success: false,
                              output: "Accessibility permission not granted. Enable in System Settings > Privacy & Security > Accessibility.")
        }
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        let depth: Int
        if case .integer(let d) = arguments["depth"] { depth = min(max(d, 1), 6) } else { depth = 3 }

        switch action {
        case "list_apps":    return listApps()
        case "inspect":      return try inspectApp(arguments: arguments, depth: depth)
        case "read_focused": return readFocusedElement()
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func listApps() -> ToolResult {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .sorted()
        return ToolResult(toolName: name, success: true,
                          output: "Running apps:\n" + apps.map { "  • \($0)" }.joined(separator: "\n"))
    }

    private func inspectApp(arguments: [String: ToolArgumentValue], depth: Int) throws -> ToolResult {
        guard let appName = arguments["app_name"]?.stringValue else {
            throw ToolError.missingRequiredParameter("app_name")
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == appName.lowercased()
        }) else {
            return ToolResult(toolName: name, success: false, output: "App not found: \(appName)")
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var lines: [String] = ["Accessibility tree for \(appName):"]
        traverseElement(appElement, indent: 0, maxDepth: depth, lines: &lines)

        let output = lines.joined(separator: "\n")
        let maxChars = 8_000
        let truncated = output.count > maxChars ? String(output.prefix(maxChars)) + "\n... [truncated]" : output
        return ToolResult(toolName: name, success: true, output: truncated)
    }

    private func readFocusedElement() -> ToolResult {
        var focusedApp: AnyObject?
        AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard let appElement = focusedApp else {
            return ToolResult(toolName: name, success: false, output: "Could not get focused application")
        }

        var focusedElement: AnyObject?
        AXUIElementCopyAttributeValue(appElement as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard let element = focusedElement else {
            return ToolResult(toolName: name, success: false, output: "No focused element found")
        }

        var lines: [String] = ["Focused element:"]
        describeElement(element as! AXUIElement, lines: &lines)
        return ToolResult(toolName: name, success: true, output: lines.joined(separator: "\n"))
    }

    // MARK: - Helpers

    private func traverseElement(_ element: AXUIElement, indent: Int, maxDepth: Int, lines: inout [String]) {
        guard indent <= maxDepth else { return }
        describeElement(element, lines: &lines, indent: indent)

        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else { return }

        for child in childArray {
            traverseElement(child, indent: indent + 1, maxDepth: maxDepth, lines: &lines)
        }
    }

    private func describeElement(_ element: AXUIElement, lines: inout [String], indent: Int = 0) {
        let prefix = String(repeating: "  ", count: indent)
        var role: AnyObject?; AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        var label: AnyObject?; AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &label)
        var value: AnyObject?; AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)

        let roleStr  = role  as? String ?? "?"
        let labelStr = label as? String ?? ""
        let valueStr = value as? String ?? ""

        var parts = [roleStr]
        if !labelStr.isEmpty { parts.append("label=\"\(labelStr)\"") }
        if !valueStr.isEmpty { parts.append("value=\"\(String(valueStr.prefix(80)))\"") }
        lines.append("\(prefix)[\(parts.joined(separator: " "))]")
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `ApplicationServices` — `AXUIElement*` | macOS Accessibility tree traversal |
| `AXIsProcessTrusted()` | Check if the app has the Accessibility permission |
| `NSWorkspace.shared.runningApplications` | Find a running app's `NSRunningApplication` to get its PID |
| `AXUIElementCreateApplication(pid)` | Create the root AX element for a given process |

### Key Implementation Steps

1. **Permission check** — call `AXIsProcessTrusted()` at the start of every invocation. If `false`, return a message directing the user to enable access in System Settings.
2. **App lookup** — find the target app in `NSWorkspace.shared.runningApplications` by a case-insensitive name match. Extract `processIdentifier` to create the `AXUIElement`.
3. **Tree traversal** — recursively call `AXUIElementCopyAttributeValue(element, kAXChildrenAttribute)` to walk the tree. Limit depth to prevent runaway recursion (complex apps like Xcode have very deep trees).
4. **Element description** — read `kAXRoleAttribute`, `kAXTitleAttribute`, and `kAXValueAttribute` for each element. Truncate long value strings to 80 characters.
5. **Focused element** — `AXUIElementCreateSystemWide()` + `kAXFocusedApplicationAttribute` + `kAXFocusedUIElementAttribute` chain to get the element under the keyboard cursor.

### Output Truncation

`maxChars = 8_000` with `"... [truncated]"` suffix. Use `depth` parameter to control verbosity.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.mach-lookup.global-name` | May be needed for cross-process AX API on newer macOS versions |

> **Accessibility permission** — the user must grant the app Accessibility access in System Settings > Privacy & Security > Accessibility. This is separate from entitlements and must be done manually.

---

## Example Tool Calls

```json
{"tool": "accessibility_inspector", "arguments": {"action": "list_apps"}}
```

```json
{"tool": "accessibility_inspector", "arguments": {"action": "inspect", "app_name": "Safari", "depth": 2}}
```

```json
{"tool": "accessibility_inspector", "arguments": {"action": "read_focused"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Accessibility permission not granted | Returns descriptive message with System Settings path |
| App not running | Returns `"App not found: <name>"` |
| `AXUIElementCopyAttributeValue` returns error | Skip that attribute silently; continue traversal |
| Very large tree (e.g. Xcode) | Truncated at `maxChars`; user can reduce `depth` |

---

## Edge Cases

- **Sandboxed target apps** — some apps restrict their AX tree visibility. The tool returns whatever is accessible.
- **System UI elements** — `AXUIElementCreateSystemWide()` can access menu bars and status items but may return `kAXErrorCannotComplete` for protected system elements.
- **Dynamic UIs** — the tree is a snapshot at query time. Web page content in Safari requires `kAXWebAreaAttribute` traversal.

---

## See Also

- [ScreenAutomationTool](./ScreenAutomationTool.md)
- [AppleScriptTool](./AppleScriptTool.md)
- [ProcessManagerTool](./ProcessManagerTool.md)
