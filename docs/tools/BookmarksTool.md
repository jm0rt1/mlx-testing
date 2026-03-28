# BookmarksTool

**Category:** Productivity & Personal Data
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `bookmarks`

## Overview

`BookmarksTool` reads Safari bookmarks from the system's bookmarks plist file. It is read-only and safe for automatic use. Adding bookmarks requires writing to the Safari plist and is deferred to future implementation.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list`, `search` |
| `query` | string | No | — | Keyword to filter bookmark titles or URLs |
| `max_results` | integer | No | `50` | Maximum results to return |

---

## Swift Implementation

```swift
import Foundation

struct BookmarksTool: AgentTool {

    let name = "bookmarks"
    let toolDescription = "List and search Safari bookmarks. Read-only access via the Safari bookmarks plist."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",      type: .string,  description: "list | search",
                      required: true, enumValues: ["list", "search"]),
        ToolParameter(name: "query",       type: .string,  description: "Filter keyword",            required: false),
        ToolParameter(name: "max_results", type: .integer, description: "Max results (default 50)",  required: false, defaultValue: "50"),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }
        let maxResults: Int
        if case .integer(let m) = arguments["max_results"] { maxResults = min(m, 200) } else { maxResults = 50 }
        let query = arguments["query"]?.stringValue?.lowercased()

        let bookmarks = loadBookmarks()
        let filtered  = query.map { q in bookmarks.filter { $0.title.lowercased().contains(q) || $0.url.lowercased().contains(q) } } ?? bookmarks

        let limited = Array(filtered.prefix(maxResults))
        let lines   = limited.map { "  \($0.title)\n    → \($0.url)" }
        let output  = "Bookmarks (\(limited.count) of \(filtered.count)):\n" + (lines.isEmpty ? "(none)" : lines.joined(separator: "\n"))
        let truncated = output.count > 8_000 ? String(output.prefix(8_000)) + "\n... [truncated]" : output
        return ToolResult(toolName: name, success: true, output: truncated)
    }

    // MARK: - Bookmark Loading

    private struct Bookmark { let title: String; let url: String }

    private func loadBookmarks() -> [Bookmark] {
        let path = NSHomeDirectory() + "/Library/Safari/Bookmarks.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return []
        }
        var results: [Bookmark] = []
        extractBookmarks(from: plist, into: &results)
        return results
    }

    private func extractBookmarks(from node: [String: Any], into results: inout [Bookmark]) {
        // Leaf bookmark
        if let title = node["URIDictionary"] as? [String: Any],
           let url   = node["URLString"] as? String {
            let name = title["title"] as? String ?? url
            results.append(Bookmark(title: name, url: url))
        }
        // Recurse into children
        if let children = node["Children"] as? [[String: Any]] {
            for child in children {
                extractBookmarks(from: child, into: &results)
            }
        }
    }
}
```

---

## Implementation Approach

### Key Implementation Steps

1. Parse `~/Library/Safari/Bookmarks.plist` as a `PropertyList` dictionary.
2. Recursively traverse the tree — each leaf node has `"URLString"` and `"URIDictionary"`.
3. Filter by keyword (title or URL) if provided.
4. Cap and format results.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Read `~/Library/Safari/Bookmarks.plist` |

---

## Example Tool Calls

```json
{"tool": "bookmarks", "arguments": {"action": "search", "query": "swift"}}
```

---

## See Also

- [SafariBrowserTool](./SafariBrowserTool.md)
- [WebSearchTool](./WebSearchTool.md)
