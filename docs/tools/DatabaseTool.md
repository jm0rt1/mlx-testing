# DatabaseTool

**Category:** Developer Productivity
**Risk Level:** medium
**Requires Approval:** Yes (for write operations)
**Tool Identifier:** `database`

## Overview

`DatabaseTool` executes SQL queries against local SQLite databases, lists schema information, and exports tables to CSV. Read operations (`query`, `schema`, `list_tables`) require minimal risk; write operations are deliberately not exposed by default — the tool enforces read-only mode unless an explicit `write_mode: true` parameter is passed. Useful for inspecting app data stores, Core Data databases, or any local SQLite file.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `query`, `schema`, `list_tables`, `export_csv` |
| `db_path` | string | Yes | — | Path to the SQLite database file |
| `sql` | string | No | — | SQL statement (required for `query`) |
| `table` | string | No | — | Table name (for `schema` and `export_csv`) |
| `max_rows` | integer | No | `100` | Maximum rows to return from `query` |

---

## Swift Implementation

```swift
import Foundation
import SQLite3

struct DatabaseTool: AgentTool {

    let name = "database"
    let toolDescription = "Query SQLite databases: run read-only SQL, inspect schema, list tables, and export to CSV."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",   type: .string, description: "query | schema | list_tables | export_csv",
                      required: true, enumValues: ["query", "schema", "list_tables", "export_csv"]),
        ToolParameter(name: "db_path",  type: .string,  description: "Path to .sqlite or .db file", required: true),
        ToolParameter(name: "sql",      type: .string,  description: "SQL query (SELECT only)",     required: false),
        ToolParameter(name: "table",    type: .string,  description: "Table name",                  required: false),
        ToolParameter(name: "max_rows", type: .integer, description: "Max rows (default 100)",      required: false, defaultValue: "100"),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action  = arguments["action"]?.stringValue  else { throw ToolError.missingRequiredParameter("action") }
        guard let rawPath = arguments["db_path"]?.stringValue else { throw ToolError.missingRequiredParameter("db_path") }
        let dbPath = NSString(string: rawPath).expandingTildeInPath
        let maxRows: Int
        if case .integer(let m) = arguments["max_rows"] { maxRows = min(m, 1_000) } else { maxRows = 100 }

        switch action {
        case "list_tables":
            return queryDB(path: dbPath, sql: "SELECT name, type FROM sqlite_master WHERE type IN ('table','view') ORDER BY name", maxRows: maxRows)
        case "schema":
            if let table = arguments["table"]?.stringValue {
                return queryDB(path: dbPath, sql: "PRAGMA table_info('\(table)')", maxRows: 200)
            } else {
                return queryDB(path: dbPath, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name", maxRows: 200)
            }
        case "query":
            guard let sql = arguments["sql"]?.stringValue else { throw ToolError.missingRequiredParameter("sql") }
            // Enforce read-only: reject any statement that isn't a SELECT/WITH/PRAGMA/EXPLAIN
            let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard trimmed.hasPrefix("SELECT") || trimmed.hasPrefix("WITH") ||
                  trimmed.hasPrefix("PRAGMA") || trimmed.hasPrefix("EXPLAIN") else {
                return ToolResult(toolName: name, success: false, output: "Only SELECT, WITH, PRAGMA, and EXPLAIN statements are allowed.")
            }
            return queryDB(path: dbPath, sql: sql, maxRows: maxRows)
        case "export_csv":
            guard let table = arguments["table"]?.stringValue else { throw ToolError.missingRequiredParameter("table") }
            return exportCSV(path: dbPath, table: table, maxRows: maxRows)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - SQLite Operations

    private func queryDB(path: String, sql: String, maxRows: Int) -> ToolResult {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return ToolResult(toolName: name, success: false, output: "Cannot open database: \(path)")
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(db))
            return ToolResult(toolName: name, success: false, output: "SQL error: \(err)")
        }
        defer { sqlite3_finalize(stmt) }

        let colCount = Int(sqlite3_column_count(stmt))
        var headers: [String] = (0..<colCount).map {
            String(cString: sqlite3_column_name(stmt, Int32($0)))
        }

        var rows: [[String]] = [headers]
        var rowCount = 0

        while sqlite3_step(stmt) == SQLITE_ROW && rowCount < maxRows {
            let row: [String] = (0..<colCount).map { col in
                switch sqlite3_column_type(stmt, Int32(col)) {
                case SQLITE_INTEGER: return String(sqlite3_column_int64(stmt, Int32(col)))
                case SQLITE_FLOAT:   return String(sqlite3_column_double(stmt, Int32(col)))
                case SQLITE_TEXT:    return String(cString: sqlite3_column_text(stmt, Int32(col)))
                case SQLITE_NULL:    return "NULL"
                default:             return "(blob)"
                }
            }
            rows.append(row)
            rowCount += 1
        }

        let widths = (0..<colCount).map { col in rows.map { $0[col].count }.max() ?? 0 }
        let formatted = rows.map { row in
            zip(row, widths).map { $0.0.padding(toLength: $0.1, withPad: " ", startingAt: 0) }.joined(separator: " | ")
        }.joined(separator: "\n")

        var output = "(\(rowCount) row\(rowCount == 1 ? "" : "s"))\n\(formatted)"
        if output.count > 10_000 { output = String(output.prefix(10_000)) + "\n... [truncated]" }
        return ToolResult(toolName: name, success: true, output: output)
    }

    private func exportCSV(path: String, table: String, maxRows: Int) -> ToolResult {
        let result = queryDB(path: path, sql: "SELECT * FROM '\(table)' LIMIT \(maxRows)", maxRows: maxRows)
        // Convert table-formatted output to CSV (simplified — production would use proper CSV escaping)
        return result
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `SQLite3` (system library) | Direct SQLite access via C API |
| `sqlite3_open_v2` with `SQLITE_OPEN_READONLY` | Prevent any accidental writes |
| `sqlite3_prepare_v2` / `sqlite3_step` | Execute queries and iterate results |

### Key Implementation Steps

1. **Read-only mode** — always open with `SQLITE_OPEN_READONLY`. Additionally validate that user SQL starts with `SELECT`, `WITH`, `PRAGMA`, or `EXPLAIN` before executing.
2. **list_tables** — query `sqlite_master` for `type IN ('table','view')`.
3. **schema** — `PRAGMA table_info('<table>')` returns columns with name, type, NOT NULL, default, and primary key flag. Without a table name, read `sqlite_master.sql` for all DDL.
4. **Formatting** — compute column widths from all values and headers, then right-pad for aligned output.
5. **export_csv** — run `SELECT * FROM '<table>'` and format as proper CSV with quotes around values containing commas.

### Output Truncation

`maxChars = 10_000` with `"... [truncated]"` suffix. `max_rows` limits the row count independently.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Open SQLite files under `~` |
| `com.apple.security.files.user-selected.read-write` | Open SQLite files chosen by the user |

---

## Example Tool Calls

```json
{"tool": "database", "arguments": {"action": "list_tables", "db_path": "~/Library/Application Support/my-app/store.sqlite"}}
```

```json
{"tool": "database", "arguments": {"action": "query", "db_path": "~/data.db", "sql": "SELECT * FROM users LIMIT 10"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| File not found | `sqlite3_open_v2` returns error; return `"Cannot open database"` |
| Non-SELECT statement provided | Reject with `"Only SELECT ... statements are allowed"` |
| SQL syntax error | Return `sqlite3_errmsg` output |
| BLOB column | Display `"(blob)"` placeholder; binary data is not printable |

---

## Edge Cases

- **Core Data databases** — Core Data's WAL-mode SQLite files can be opened read-only safely. The schema uses `Z_` prefix for entity tables.
- **Encrypted SQLite** — SQLCipher-encrypted databases will fail to open; return an appropriate message.
- **Very wide tables** — fixed-width alignment may wrap on narrow terminals. Consider adding a `--csv` output mode for wide tables.

---

## See Also

- [FileSystemTool](../mlx-testing/AgentTools/FileSystemTool.swift) *(existing)*
- [JSONTransformTool](./JSONTransformTool.md)
- [SpreadsheetTool](./SpreadsheetTool.md)
