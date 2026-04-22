# SpotlightTool

**Category:** macOS System & Hardware
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `spotlight`

## Overview

`SpotlightTool` searches the local file system using macOS Spotlight's metadata index (`NSMetadataQuery`). It supports full-text search, metadata filters (kind, date, author, file extension), and returns file paths with key attributes. Unlike a shell `find` command, Spotlight queries are nearly instantaneous because they use a pre-built index. This tool is read-only and safe for automatic use.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `query` | string | Yes | — | Search query string (keywords, file name, or `kMDItem*` predicate) |
| `scope` | string | No | `"home"` | Search scope: `home`, `computer`, or an absolute directory path |
| `kind` | string | No | — | Filter by file kind: e.g. `"pdf"`, `"image"`, `"source code"`, `"spreadsheet"` |
| `extension` | string | No | — | Filter by file extension (without dot), e.g. `"swift"` |
| `max_results` | integer | No | `20` | Maximum number of results to return (max 100) |

---

## Swift Implementation

```swift
import Foundation

struct SpotlightTool: AgentTool {

    let name = "spotlight"
    let toolDescription = "Search the local file system using the Spotlight metadata index. Fast, full-text and metadata search."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "query",       type: .string,  description: "Search query",         required: true),
        ToolParameter(name: "scope",       type: .string,  description: "home | computer | /path", required: false, defaultValue: "home"),
        ToolParameter(name: "kind",        type: .string,  description: "File kind filter",     required: false),
        ToolParameter(name: "extension",   type: .string,  description: "File extension filter (no dot)", required: false),
        ToolParameter(name: "max_results", type: .integer, description: "Max results (default 20, max 100)", required: false, defaultValue: "20"),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let queryStr = arguments["query"]?.stringValue else {
            throw ToolError.missingRequiredParameter("query")
        }

        let maxResults: Int
        if case .integer(let m) = arguments["max_results"] { maxResults = min(m, 100) } else { maxResults = 20 }

        // Build predicate
        var predicateParts: [String] = [
            "(kMDItemDisplayName CONTAINS[cd] '\(queryStr)' || kMDItemTextContent CONTAINS[cd] '\(queryStr)')"
        ]
        if let kind = arguments["kind"]?.stringValue {
            predicateParts.append("kMDItemKind CONTAINS[cd] '\(kind)'")
        }
        if let ext = arguments["extension"]?.stringValue {
            predicateParts.append("kMDItemFSName ENDSWITH[cd] '.\(ext)'")
        }
        let predicateString = predicateParts.joined(separator: " && ")

        // Build scope URLs
        let scopeStr = arguments["scope"]?.stringValue ?? "home"
        let scopeURLs: [URL]
        switch scopeStr {
        case "home":
            scopeURLs = [URL(fileURLWithPath: NSHomeDirectory())]
        case "computer":
            scopeURLs = [NSMetadataQueryLocalComputerScope] as! [URL]  // uses NSMetadataQueryLocalComputerScope constant
        default:
            scopeURLs = [URL(fileURLWithPath: scopeStr)]
        }

        return await withCheckedContinuation { continuation in
            runQuery(predicate: predicateString, scopes: scopeURLs, maxResults: maxResults) { results in
                continuation.resume(returning: results)
            }
        }
    }

    // MARK: - NSMetadataQuery

    private func runQuery(predicate: String, scopes: [URL], maxResults: Int,
                          completion: @escaping (ToolResult) -> Void) {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: predicate)
        query.searchScopes = scopes
        query.sortDescriptors = [NSSortDescriptor(key: kMDItemFSContentChangeDate as String, ascending: false)]

        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query, queue: .main
        ) { _ in
            query.stop()
            if let obs = observer { NotificationCenter.default.removeObserver(obs) }

            let count = min(query.resultCount, maxResults)
            var lines: [String] = []
            for i in 0..<count {
                guard let item = query.result(at: i) as? NSMetadataItem else { continue }
                let path = item.value(forAttribute: kMDItemPath as String) as? String ?? "?"
                let name = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? "?"
                let kind = item.value(forAttribute: kMDItemKind as String) as? String ?? "?"
                let size = item.value(forAttribute: kMDItemFSSize as String) as? Int ?? 0
                lines.append("  \(name) [\(kind), \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))]\n    → \(path)")
            }

            let output: String
            if lines.isEmpty {
                output = "No results found for '\(predicate)'"
            } else {
                output = "Spotlight results (\(query.resultCount) total, showing \(count)):\n" + lines.joined(separator: "\n")
            }
            let truncated = output.count > 8_000 ? String(output.prefix(8_000)) + "\n... [truncated]" : output
            completion(ToolResult(toolName: "spotlight", success: true, output: truncated))
        }

        query.start()

        // Timeout safety
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if query.isStarted { query.stop() }
        }
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `NSMetadataQuery` | Execute Spotlight queries with predicates and scopes |
| `NSMetadataItem` | Read attributes: `kMDItemPath`, `kMDItemDisplayName`, `kMDItemKind`, `kMDItemFSSize`, `kMDItemTextContent` |
| `NSMetadataQueryLocalComputerScope` | Search all local volumes |

### Key Implementation Steps

1. **Predicate** — build an `NSPredicate` combining `kMDItemDisplayName CONTAINS[cd]` (case/diacritic insensitive) and `kMDItemTextContent CONTAINS[cd]` with `||`. Append `kMDItemKind CONTAINS[cd]` and `kMDItemFSName ENDSWITH[cd]` for kind and extension filters.
2. **Scope** — `"home"` uses `NSHomeDirectory()`; `"computer"` uses `NSMetadataQueryLocalComputerScope`; any other value is treated as a directory path.
3. **Execution** — `NSMetadataQuery` is asynchronous. Start it, observe `.NSMetadataQueryDidFinishGathering`, stop the query in the handler, extract results.
4. **Timeout** — stop the query after 10 seconds if it hasn't finished (large indexes can be slow for text content searches).
5. **Formatting** — display each result with name, kind, size, and full path. Cap at `maxResults` and truncate the output string at 8,000 characters.

### Output Truncation

`maxChars = 8_000` with `"... [truncated]"` suffix.

---

## Sandbox Entitlements

Spotlight (`NSMetadataQuery`) works within the sandbox. Searching outside the home directory with the `"computer"` scope may prompt for Full Disk Access depending on macOS version.

---

## Example Tool Calls

```json
{"tool": "spotlight", "arguments": {"query": "WWDC session notes", "kind": "pdf", "max_results": 10}}
```

```json
{"tool": "spotlight", "arguments": {"query": "ChatViewModel", "extension": "swift", "scope": "home"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Spotlight index disabled / unavailable | Query returns 0 results; note `"mdutil -s /"` to check indexing status |
| Query times out after 10 s | Returns whatever partial results were gathered |
| Invalid predicate string | `NSPredicate` initialiser returns `nil`; throw `ToolError.executionFailed` |

---

## Edge Cases

- **External drives** — only indexed if the drive has Spotlight indexing enabled (`mdutil -s /Volumes/MyDrive`).
- **Privacy-sensitive directories** — `~/Library` is excluded from Spotlight results by default on some macOS versions.
- **`kMDItemTextContent`** — only available for file types that Spotlight has importers for (PDF, Office docs, plain text, source code). Binary files return no text content match.

---

## See Also

- [FileSystemTool](../mlx-testing/AgentTools/FileSystemTool.swift) *(existing)*
- [AccessibilityInspectorTool](./AccessibilityInspectorTool.md)
