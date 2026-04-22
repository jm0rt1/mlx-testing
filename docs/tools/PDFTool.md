# PDFTool

**Category:** Files & Documents
**Risk Level:** medium
**Requires Approval:** Yes (for mutating actions)
**Tool Identifier:** `pdf`

## Overview

`PDFTool` works with PDF files using Apple's `PDFKit` framework. Read operations (`extract_text`, `page_count`) are low risk; write operations (`merge`, `split`, `rotate`) modify files and require approval. Useful for extracting document content for RAG, splitting presentations, or merging reports.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `extract_text`, `page_count`, `merge`, `split`, `rotate` |
| `path` | string | No | — | Input PDF file path (required for most actions) |
| `paths` | string | No | — | Comma-separated list of PDF paths (for `merge`) |
| `output_path` | string | No | — | Output file path (for `merge`, `split`, `rotate`) |
| `page_range` | string | No | `"1-end"` | Page range to extract or split, e.g. `"1-5"` or `"3"` |
| `rotation` | integer | No | `90` | Rotation degrees: `90`, `180`, `270` (for `rotate`) |

---

## Swift Implementation

```swift
import Foundation
import PDFKit

struct PDFTool: AgentTool {

    let name = "pdf"
    let toolDescription = "Work with PDF files: extract text, count pages, merge multiple PDFs, split into pages, and rotate pages."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",      type: .string, description: "extract_text | page_count | merge | split | rotate",
                      required: true, enumValues: ["extract_text", "page_count", "merge", "split", "rotate"]),
        ToolParameter(name: "path",        type: .string,  description: "Input PDF path",                  required: false),
        ToolParameter(name: "paths",       type: .string,  description: "Comma-separated PDF paths",       required: false),
        ToolParameter(name: "output_path", type: .string,  description: "Output PDF path",                 required: false),
        ToolParameter(name: "page_range",  type: .string,  description: "Page range, e.g. '1-5' or '3'",  required: false, defaultValue: "1-end"),
        ToolParameter(name: "rotation",    type: .integer, description: "Rotation degrees 90|180|270",     required: false, defaultValue: "90"),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }

        switch action {
        case "extract_text": return try extractText(arguments: arguments)
        case "page_count":   return try pageCount(arguments: arguments)
        case "merge":        return try merge(arguments: arguments)
        case "split":        return try split(arguments: arguments)
        case "rotate":       return try rotate(arguments: arguments)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func extractText(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        let path = try resolvePath(arguments["path"])
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
            return ToolResult(toolName: name, success: false, output: "Cannot open PDF: \(path)")
        }
        let range = parsePageRange(arguments["page_range"]?.stringValue, totalPages: document.pageCount)
        var text = ""
        for i in range {
            guard let page = document.page(at: i) else { continue }
            text += page.string ?? ""
            text += "\n"
        }
        let maxChars = 10_000
        let output = text.count > maxChars ? String(text.prefix(maxChars)) + "\n... [truncated at \(maxChars) chars]" : text
        return ToolResult(toolName: name, success: true, output: output.isEmpty ? "(no text extracted)" : output)
    }

    private func pageCount(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        let path = try resolvePath(arguments["path"])
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
            return ToolResult(toolName: name, success: false, output: "Cannot open PDF: \(path)")
        }
        return ToolResult(toolName: name, success: true, output: "\(path): \(document.pageCount) page(s)")
    }

    private func merge(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let pathsStr = arguments["paths"]?.stringValue else { throw ToolError.missingRequiredParameter("paths") }
        let outputPath = arguments["output_path"]?.stringValue ?? (NSHomeDirectory() + "/Desktop/merged.pdf")
        let paths = pathsStr.components(separatedBy: ",").map { NSString(string: $0.trimmingCharacters(in: .whitespaces)).expandingTildeInPath as String }

        let merged = PDFDocument()
        var pageIndex = 0
        for path in paths {
            guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
                return ToolResult(toolName: name, success: false, output: "Cannot open: \(path)")
            }
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                merged.insert(page, at: pageIndex)
                pageIndex += 1
            }
        }
        let outURL = URL(fileURLWithPath: NSString(string: outputPath).expandingTildeInPath)
        merged.write(to: outURL)
        return ToolResult(toolName: name, success: true, output: "Merged \(paths.count) PDFs into \(outURL.path) (\(merged.pageCount) pages)",
                          artifacts: [ToolArtifact(type: .filePath, label: "Merged PDF", value: outURL.path)])
    }

    private func split(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        let inputPath = try resolvePath(arguments["path"])
        guard let document = PDFDocument(url: URL(fileURLWithPath: inputPath)) else {
            return ToolResult(toolName: name, success: false, output: "Cannot open PDF: \(inputPath)")
        }
        let range = parsePageRange(arguments["page_range"]?.stringValue, totalPages: document.pageCount)
        let outputDir = arguments["output_path"]?.stringValue ?? (NSHomeDirectory() + "/Desktop/split_pages")
        try FileManager.default.createDirectory(atPath: NSString(string: outputDir).expandingTildeInPath, withIntermediateDirectories: true)

        for i in range {
            guard let page = document.page(at: i) else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let outPath = NSString(string: outputDir).expandingTildeInPath + "/page_\(i + 1).pdf"
            single.write(to: URL(fileURLWithPath: outPath))
        }
        return ToolResult(toolName: name, success: true, output: "Split \(range.count) page(s) to \(outputDir)")
    }

    private func rotate(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        let inputPath = try resolvePath(arguments["path"])
        guard let document = PDFDocument(url: URL(fileURLWithPath: inputPath)) else {
            return ToolResult(toolName: name, success: false, output: "Cannot open PDF: \(inputPath)")
        }
        let degrees: Int
        if case .integer(let d) = arguments["rotation"] { degrees = d } else { degrees = 90 }
        let range = parsePageRange(arguments["page_range"]?.stringValue, totalPages: document.pageCount)
        for i in range {
            document.page(at: i)?.rotation = degrees
        }
        let outputPath = arguments["output_path"]?.stringValue ?? inputPath
        document.write(to: URL(fileURLWithPath: NSString(string: outputPath).expandingTildeInPath))
        return ToolResult(toolName: name, success: true, output: "Rotated \(range.count) page(s) by \(degrees)°")
    }

    // MARK: - Helpers

    private func resolvePath(_ raw: ToolArgumentValue?) throws -> String {
        guard let r = raw?.stringValue else { throw ToolError.missingRequiredParameter("path") }
        return NSString(string: r).expandingTildeInPath
    }

    private func parsePageRange(_ rangeStr: String?, totalPages: Int) -> Range<Int> {
        guard let str = rangeStr, !str.isEmpty, str != "1-end" else { return 0..<totalPages }
        if str.contains("-") {
            let parts = str.split(separator: "-")
            let start = (Int(parts.first ?? "1") ?? 1) - 1
            let endStr = parts.last.map(String.init) ?? "end"
            let end   = endStr == "end" ? totalPages : (Int(endStr) ?? totalPages)
            return max(0, start)..<min(end, totalPages)
        } else if let page = Int(str) {
            let idx = page - 1
            return max(0, idx)..<min(idx + 1, totalPages)
        }
        return 0..<totalPages
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `PDFKit` — `PDFDocument`, `PDFPage` | All PDF read/write operations |
| `PDFPage.string` | Extract the text content of a single page |
| `PDFDocument.insert(_:at:)` / `write(to:)` | Assemble and save modified PDFs |

### Key Implementation Steps

1. **extract_text** — iterate pages in the requested range; concatenate `PDFPage.string` values. Apply `maxChars = 10_000`.
2. **page_count** — `PDFDocument(url:).pageCount`.
3. **merge** — create an empty `PDFDocument`; iterate source files and insert all pages in order; `write(to:)`.
4. **split** — create one single-page `PDFDocument` per page in the range; write each to `page_N.pdf` in the output directory.
5. **rotate** — set `PDFPage.rotation` (in degrees); write the modified document back.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.files.user-selected.read-write` | Read/write user-selected PDF files |
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Access PDFs under `~` |

---

## Example Tool Calls

```json
{"tool": "pdf", "arguments": {"action": "extract_text", "path": "~/Documents/report.pdf", "page_range": "1-3"}}
```

```json
{"tool": "pdf", "arguments": {"action": "merge", "paths": "~/a.pdf, ~/b.pdf", "output_path": "~/merged.pdf"}}
```

---

## See Also

- [FileSystemTool](../mlx-testing/AgentTools/FileSystemTool.swift) *(existing)*
- [MarkdownTool](./MarkdownTool.md)
- [SpreadsheetTool](./SpreadsheetTool.md)
