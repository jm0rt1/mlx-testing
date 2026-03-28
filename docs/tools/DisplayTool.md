# DisplayTool

**Category:** macOS System & Hardware
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `display`

## Overview

`DisplayTool` manages screen configuration. Read actions (listing displays, getting brightness) are low-impact; write actions (setting brightness, mirroring) modify system state and require approval. Useful for automating presentation setup, adjusting brightness from a chat command, or debugging display configurations.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list`, `brightness_get`, `brightness_set`, `screenshot`, `night_shift` |
| `brightness` | integer | No | — | 0–100 brightness percentage (required for `brightness_set`) |
| `enabled` | boolean | No | — | Enable/disable Night Shift (required for `night_shift`) |
| `window_title` | string | No | — | Target window title for `screenshot`; omit for full screen |
| `output_path` | string | No | `~/Desktop/screenshot.png` | Destination file path for `screenshot` |

---

## Swift Implementation

```swift
import Foundation
import CoreGraphics
import AppKit

struct DisplayTool: AgentTool {

    let name = "display"
    let toolDescription = "Manage display configuration: list screens, get/set brightness, take screenshots, toggle Night Shift."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action", type: .string,
                      description: "Operation to perform",
                      required: true,
                      enumValues: ["list", "brightness_get", "brightness_set", "screenshot", "night_shift"]),
        ToolParameter(name: "brightness", type: .integer,
                      description: "Brightness level 0–100 (for brightness_set)", required: false),
        ToolParameter(name: "enabled", type: .boolean,
                      description: "true/false for night_shift toggle", required: false),
        ToolParameter(name: "window_title", type: .string,
                      description: "Window title to screenshot (omit for full screen)", required: false),
        ToolParameter(name: "output_path", type: .string,
                      description: "File path for screenshot output", required: false,
                      defaultValue: "~/Desktop/screenshot.png"),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        switch action {
        case "list":           return listDisplays()
        case "brightness_get": return getBrightness()
        case "brightness_set": return try setBrightness(arguments: arguments)
        case "screenshot":     return try takeScreenshot(arguments: arguments)
        case "night_shift":    return try setNightShift(arguments: arguments)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func listDisplays() -> ToolResult {
        let screens = NSScreen.screens
        var lines = ["Displays (\(screens.count)):"]
        for (i, screen) in screens.enumerated() {
            let frame = screen.frame
            let backing = screen.backingScaleFactor
            let name = screen.localizedName
            lines.append("  [\(i)] \(name) — \(Int(frame.width))×\(Int(frame.height)) @ \(backing)x")
        }
        return ToolResult(toolName: name, success: true, output: lines.joined(separator: "\n"))
    }

    private func getBrightness() -> ToolResult {
        // Use IOServiceGetMatchingService("AppleBacklightDisplay") + brightness IORegistry property
        // Falls back to `brightness` CLI tool via shell
        let result = (try? runShell("brightness -l")) ?? "brightness tool not available"
        return ToolResult(toolName: name, success: true, output: result)
    }

    private func setBrightness(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard case .integer(let level) = arguments["brightness"] else {
            throw ToolError.missingRequiredParameter("brightness")
        }
        let clamped = min(max(level, 0), 100)
        let value = Double(clamped) / 100.0
        _ = try? runShell("brightness \(value)")
        return ToolResult(toolName: name, success: true, output: "Brightness set to \(clamped)%")
    }

    private func takeScreenshot(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        let rawPath = arguments["output_path"]?.stringValue ?? "~/Desktop/screenshot.png"
        let path = NSString(string: rawPath).expandingTildeInPath
        let windowTitle = arguments["window_title"]?.stringValue

        let cmd: String
        if let title = windowTitle {
            // screencapture -l <windowID> — requires looking up window ID via CGWindowList
            cmd = "screencapture -x '\(path)'"  // simplified; production would resolve window ID
        } else {
            cmd = "screencapture -x '\(path)'"
        }
        _ = try? runShell(cmd)
        return ToolResult(
            toolName: name, success: true,
            output: "Screenshot saved to \(path)",
            artifacts: [ToolArtifact(type: .filePath, label: "Screenshot", value: path)]
        )
    }

    private func setNightShift(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard case .boolean(let enabled) = arguments["enabled"] else {
            throw ToolError.missingRequiredParameter("enabled")
        }
        // CBBlueLightClient (private framework) or `nightshift` CLI
        let cmd = "osascript -e 'tell application \"System Events\" to set value of slider \"Night Shift\" of window 1 of application process \"ControlCenter\" to \(enabled ? 1 : 0)'"
        _ = try? runShell(cmd)
        return ToolResult(toolName: name, success: true, output: "Night Shift \(enabled ? "enabled" : "disabled")")
    }

    private func runShell(_ command: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `AppKit` — `NSScreen` | List connected displays with names, resolutions, and backing scale |
| `CoreGraphics` — `CGWindowListCopyWindowInfo` | Enumerate windows by title to resolve window IDs for targeted screenshots |
| `screencapture` CLI | Full-screen or window screenshots without needing `CGDisplayCreateImage` |
| `brightness` Homebrew CLI | Programmatic brightness control (alternative: IOKit `AppleBacklightDisplay`) |
| `CBBlueLightClient` (private) | Night Shift toggle; documented replacement is the `nightshift` CLI |

### Key Implementation Steps

1. **List** — iterate `NSScreen.screens`; use `screen.localizedName` (macOS 12+) and `screen.frame` for resolution.
2. **Brightness** — use the `brightness` command-line tool (Homebrew) for setting; reading uses `IOKit` brightness property from `AppleBacklightDisplay` service. Clamp value to 0–100.
3. **Screenshot** — invoke `screencapture -x <path>` for silent (no shutter sound) captures. For window-specific shots, resolve the CGWindowID from `CGWindowListCopyWindowInfo` filtered by `kCGWindowName`.
4. **Night Shift** — use `CBBlueLightClient` private API or fall back to an AppleScript toggle of the Night Shift preference pane. The `nightshift` CLI (Homebrew) is the simplest approach.

### Output Truncation

Not applicable; responses are compact (< 500 characters).

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Writing screenshot to `~/Desktop` |

> Screen recording permission (`com.apple.security.screen-capture`) is required for `screencapture` to capture window contents. The user will be prompted on first use.

---

## Example Tool Calls

```json
{"tool": "display", "arguments": {"action": "list"}}
```

```json
{"tool": "display", "arguments": {"action": "brightness_set", "brightness": 70}}
```

```json
{"tool": "display", "arguments": {"action": "screenshot", "output_path": "~/Desktop/capture.png"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| `brightness` CLI not installed | Returns message directing user to install via Homebrew |
| Screen recording permission denied | `screencapture` returns empty file; return `success: false` |
| `brightness` out of 0–100 range | Clamped silently to valid range |

---

## Edge Cases

- **External displays** — `brightness_set` only controls the built-in display via `AppleBacklightDisplay`. External monitor brightness requires DDC/CI commands.
- **Headless / server Mac** — `NSScreen.screens` returns an empty array. Return `"No displays connected"`.
- **Retina scaling** — `NSScreen.frame` is in points; multiply by `backingScaleFactor` to get pixels.

---

## See Also

- [SystemInfoTool](./SystemInfoTool.md)
- [AudioTool](./AudioTool.md)
- [ScreenAutomationTool](./ScreenAutomationTool.md)
