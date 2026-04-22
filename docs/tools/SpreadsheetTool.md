# SpreadsheetTool

**Category:** Files & Documents
**Risk Level:** medium
**Requires Approval:** Yes (for write operations)
**Tool Identifier:** `spreadsheet`

## Overview

`SpreadsheetTool` reads and writes tabular data in CSV format and provides basic analysis capabilities (filter, sort, aggregate). Reading is low risk; writing CSV back to disk requires approval. Useful for the LLM to analyse exported data, find patterns, or reformat datasets.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `read`, `filter`, `sort`, `aggregate`, `write` |
| `path` | string | Yes | — | CSV file path |
| `output_path` | string | No | — | Output CSV path (for `write`) |
| `column` | string | No | — | Column name to operate on |
| `condition` | string | No | — | Filter condition, e.g. `"age > 30"` |
| `sort_order` | string | No | `"asc"` | `asc` or `desc` (for `sort`) |
| `aggregation` | string | No | — | One of `sum`, `mean`, `min`, `max`, `count` (for `aggregate`) |
| `max_rows` | integer | No | `50` | Maximum rows to return |
| `content` | string | No | — | CSV content to write (for `write`) |

---

## Swift Implementation

```swift
import Foundation

struct SpreadsheetTool: AgentTool {

    let name = "spreadsheet"
    let toolDescription = "Read, filter, sort, and aggregate CSV data. Write modified CSV back to disk."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",      type: .string, description: "read | filter | sort | aggregate | write",
                      required: true, enumValues: ["read", "filter", "sort", "aggregate", "write"]),
        ToolParameter(name: "path",        type: .string,  description: "CSV file path",           required: true),
        ToolParameter(name: "output_path", type: .string,  description: "Output CSV path",         required: false),
        ToolParameter(name: "column",      type: .string,  description: "Column to operate on",    required: false),
        ToolParameter(name: "condition",   type: .string,  description: "Filter condition",        required: false),
        ToolParameter(name: "sort_order",  type: .string,  description: "asc | desc",              required: false, defaultValue: "asc"),
        ToolParameter(name: "aggregation", type: .string,  description: "sum|mean|min|max|count",  required: false,
                      enumValues: ["sum", "mean", "min", "max", "count"]),
        ToolParameter(name: "max_rows",    type: .integer, description: "Max rows to return",      required: false, defaultValue: "50"),
        ToolParameter(name: "content",     type: .string,  description: "CSV content to write",    required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action  = arguments["action"]?.stringValue  else { throw ToolError.missingRequiredParameter("action") }
        guard let rawPath = arguments["path"]?.stringValue    else { throw ToolError.missingRequiredParameter("path") }
        let path = NSString(string: rawPath).expandingTildeInPath
        let maxRows: Int
        if case .integer(let m) = arguments["max_rows"] { maxRows = min(m, 1_000) } else { maxRows = 50 }

        switch action {
        case "read":
            return try readCSV(path: path, maxRows: maxRows)
        case "filter":
            guard let col = arguments["column"]?.stringValue,
                  let cond = arguments["condition"]?.stringValue else {
                throw ToolError.missingRequiredParameter("column and condition")
            }
            return try filterCSV(path: path, column: col, condition: cond, maxRows: maxRows)
        case "sort":
            guard let col = arguments["column"]?.stringValue else { throw ToolError.missingRequiredParameter("column") }
            let order = arguments["sort_order"]?.stringValue ?? "asc"
            return try sortCSV(path: path, column: col, ascending: order == "asc", maxRows: maxRows)
        case "aggregate":
            guard let col = arguments["column"]?.stringValue,
                  let agg = arguments["aggregation"]?.stringValue else {
                throw ToolError.missingRequiredParameter("column and aggregation")
            }
            return try aggregateCSV(path: path, column: col, aggregation: agg)
        case "write":
            guard let content = arguments["content"]?.stringValue else { throw ToolError.missingRequiredParameter("content") }
            let outPath = arguments["output_path"]?.stringValue ?? path
            return try writeCSV(content: content, path: NSString(string: outPath).expandingTildeInPath)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - CSV Helpers

    private func parseCSV(path: String) throws -> (headers: [String], rows: [[String]]) {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return ([], []) }
        let headers = lines[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let rows = lines.dropFirst().map { line in
            line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return (headers, Array(rows))
    }

    private func formatTable(headers: [String], rows: [[String]]) -> String {
        let allRows = [headers] + rows
        let widths = (0..<headers.count).map { col in allRows.map { $0.count > col ? $0[col].count : 0 }.max() ?? 0 }
        return allRows.map { row in
            (0..<headers.count).map { col in
                let val = col < row.count ? row[col] : ""
                return val.padding(toLength: widths[col], withPad: " ", startingAt: 0)
            }.joined(separator: " | ")
        }.joined(separator: "\n")
    }

    private func readCSV(path: String, maxRows: Int) throws -> ToolResult {
        let (headers, rows) = try parseCSV(path: path)
        let limited = Array(rows.prefix(maxRows))
        var output = "Rows: \(rows.count), Columns: \(headers.count)\n" + formatTable(headers: headers, rows: limited)
        if rows.count > maxRows { output += "\n... [\(rows.count - maxRows) more rows]" }
        if output.count > 10_000 { output = String(output.prefix(10_000)) + "\n... [truncated]" }
        return ToolResult(toolName: name, success: true, output: output)
    }

    private func filterCSV(path: String, column: String, condition: String, maxRows: Int) throws -> ToolResult {
        let (headers, rows) = try parseCSV(path: path)
        guard let colIdx = headers.firstIndex(of: column) else {
            return ToolResult(toolName: name, success: false, output: "Column '\(column)' not found. Available: \(headers.joined(separator: ", "))")
        }
        // Simple condition parsing: "value > 30", "value == text", "value contains text"
        let filtered = rows.filter { row in
            let val = colIdx < row.count ? row[colIdx] : ""
            if condition.contains(">"), let n = Double(val), let threshold = Double(condition.replacingOccurrences(of: "> ", with: "")) {
                return n > threshold
            } else if condition.contains("<"), let n = Double(val), let threshold = Double(condition.replacingOccurrences(of: "< ", with: "")) {
                return n < threshold
            } else if condition.lowercased().contains("contains") {
                let search = condition.replacingOccurrences(of: "contains ", with: "", options: .caseInsensitive)
                return val.localizedCaseInsensitiveContains(search)
            }
            return val == condition
        }
        let output = "Filtered: \(filtered.count)/\(rows.count) rows\n" + formatTable(headers: headers, rows: Array(filtered.prefix(maxRows)))
        return ToolResult(toolName: name, success: true, output: output)
    }

    private func sortCSV(path: String, column: String, ascending: Bool, maxRows: Int) throws -> ToolResult {
        let (headers, rows) = try parseCSV(path: path)
        guard let colIdx = headers.firstIndex(of: column) else {
            return ToolResult(toolName: name, success: false, output: "Column '\(column)' not found.")
        }
        let sorted = rows.sorted { a, b in
            let av = colIdx < a.count ? a[colIdx] : ""
            let bv = colIdx < b.count ? b[colIdx] : ""
            if let an = Double(av), let bn = Double(bv) { return ascending ? an < bn : an > bn }
            return ascending ? av < bv : av > bv
        }
        let output = formatTable(headers: headers, rows: Array(sorted.prefix(maxRows)))
        return ToolResult(toolName: name, success: true, output: "Sorted by '\(column)' (\(ascending ? "asc" : "desc")):\n\(output)")
    }

    private func aggregateCSV(path: String, column: String, aggregation: String) throws -> ToolResult {
        let (headers, rows) = try parseCSV(path: path)
        guard let colIdx = headers.firstIndex(of: column) else {
            return ToolResult(toolName: name, success: false, output: "Column '\(column)' not found.")
        }
        let values = rows.compactMap { row -> Double? in colIdx < row.count ? Double(row[colIdx]) : nil }
        guard !values.isEmpty else {
            return ToolResult(toolName: name, success: false, output: "No numeric values in column '\(column)'")
        }
        let result: String
        switch aggregation {
        case "sum":   result = "\(values.reduce(0, +))"
        case "mean":  result = "\(values.reduce(0, +) / Double(values.count))"
        case "min":   result = "\(values.min()!)"
        case "max":   result = "\(values.max()!)"
        case "count": result = "\(values.count)"
        default:      result = "unknown"
        }
        return ToolResult(toolName: name, success: true, output: "\(aggregation)(\(column)) = \(result)")
    }

    private func writeCSV(content: String, path: String) throws -> ToolResult {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return ToolResult(toolName: name, success: true, output: "Written \(content.count) characters to \(path)",
                          artifacts: [ToolArtifact(type: .filePath, label: "CSV", value: path)])
    }
}
```

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Read/write CSV files under `~` |

---

## Example Tool Calls

```json
{"tool": "spreadsheet", "arguments": {"action": "read", "path": "~/Downloads/sales.csv", "max_rows": 20}}
```

```json
{"tool": "spreadsheet", "arguments": {"action": "aggregate", "path": "~/data.csv", "column": "revenue", "aggregation": "sum"}}
```

---

## See Also

- [DataAnalysisTool](./DataAnalysisTool.md)
- [DatabaseTool](./DatabaseTool.md)
- [JSONTransformTool](./JSONTransformTool.md)
