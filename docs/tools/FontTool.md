# FontTool

**Category:** Files & Documents
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `font`

## Overview

`FontTool` inspects fonts installed on the system using `NSFontManager` and `CTFont`. It lists all available font families, returns the styles available in a family, and locates the file path of a specific font on disk. Entirely read-only.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list_families`, `list_styles`, `find_file` |
| `family` | string | No | — | Font family name (required for `list_styles`, `find_file`) |
| `filter` | string | No | — | Keyword to filter family names (for `list_families`) |

---

## Swift Implementation

```swift
import Foundation
import AppKit
import CoreText

struct FontTool: AgentTool {

    let name = "font"
    let toolDescription = "Inspect installed fonts: list families, available styles, and locate font files on disk."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action", type: .string,
                      description: "list_families | list_styles | find_file",
                      required: true, enumValues: ["list_families", "list_styles", "find_file"]),
        ToolParameter(name: "family", type: .string, description: "Font family name",         required: false),
        ToolParameter(name: "filter", type: .string, description: "Keyword filter for families", required: false),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }

        switch action {
        case "list_families":
            return listFamilies(filter: arguments["filter"]?.stringValue)
        case "list_styles":
            guard let family = arguments["family"]?.stringValue else { throw ToolError.missingRequiredParameter("family") }
            return listStyles(family: family)
        case "find_file":
            guard let family = arguments["family"]?.stringValue else { throw ToolError.missingRequiredParameter("family") }
            return findFontFile(family: family)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func listFamilies(filter: String?) -> ToolResult {
        var families = NSFontManager.shared.availableFontFamilies
        if let f = filter?.lowercased() {
            families = families.filter { $0.lowercased().contains(f) }
        }
        let output = "Font families (\(families.count)):\n" + families.prefix(200).map { "  • \($0)" }.joined(separator: "\n")
        let truncated = output.count > 8_000 ? String(output.prefix(8_000)) + "\n... [truncated]" : output
        return ToolResult(toolName: name, success: true, output: truncated)
    }

    private func listStyles(family: String) -> ToolResult {
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        if members.isEmpty {
            return ToolResult(toolName: name, success: false, output: "Font family not found: '\(family)'")
        }
        let lines = members.compactMap { member -> String? in
            guard let name = member[0] as? String,
                  let style = member[1] as? String else { return nil }
            return "  \(style) — PostScript: \(name)"
        }
        return ToolResult(toolName: name, success: true,
                          output: "Styles in '\(family)' (\(lines.count)):\n" + lines.joined(separator: "\n"))
    }

    private func findFontFile(family: String) -> ToolResult {
        // Use CTFontDescriptor to get the font URL
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: family
        ] as CFDictionary)
        guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL else {
            return ToolResult(toolName: name, success: false, output: "Font file not found for family: '\(family)'")
        }
        return ToolResult(toolName: name, success: true,
                          output: "Font file for '\(family)':\n  \(url.path)",
                          artifacts: [ToolArtifact(type: .filePath, label: "Font file", value: url.path)])
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `AppKit` — `NSFontManager` | `availableFontFamilies`, `availableMembers(ofFontFamily:)` |
| `CoreText` — `CTFontDescriptor`, `kCTFontURLAttribute` | Resolve font file path |

---

## Example Tool Calls

```json
{"tool": "font", "arguments": {"action": "list_families", "filter": "Helvetica"}}
```

```json
{"tool": "font", "arguments": {"action": "find_file", "family": "SF Pro"}}
```

---

## See Also

- [ImageProcessingTool](./ImageProcessingTool.md)
