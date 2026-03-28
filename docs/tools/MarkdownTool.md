# MarkdownTool

**Category:** Files & Documents
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `markdown`

## Overview

`MarkdownTool` parses and analyses Markdown documents without modifying them. It can extract document structure (headings, links, images), convert to HTML, generate a table of contents, and count words and reading time. Entirely read-only and safe for automatic execution.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `structure`, `to_html`, `toc`, `word_count` |
| `path` | string | No | — | Path to a Markdown file (mutually exclusive with `content`) |
| `content` | string | No | — | Markdown string to process (alternative to `path`) |

---

## Swift Implementation

```swift
import Foundation

struct MarkdownTool: AgentTool {

    let name = "markdown"
    let toolDescription = "Parse and analyse Markdown: extract structure, convert to HTML, generate a table of contents, count words."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",  type: .string, description: "structure | to_html | toc | word_count",
                      required: true, enumValues: ["structure", "to_html", "toc", "word_count"]),
        ToolParameter(name: "path",    type: .string, description: "Markdown file path",    required: false),
        ToolParameter(name: "content", type: .string, description: "Markdown string input", required: false),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }
        let markdown = try loadMarkdown(arguments: arguments)

        switch action {
        case "structure":   return analyseStructure(markdown: markdown)
        case "to_html":     return convertToHTML(markdown: markdown)
        case "toc":         return generateTOC(markdown: markdown)
        case "word_count":  return countWords(markdown: markdown)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func analyseStructure(markdown: String) -> ToolResult {
        let lines = markdown.components(separatedBy: "\n")
        var sections: [String] = []
        var links: [String] = []
        var images: [String] = []
        var codeBlocks = 0

        for line in lines {
            if line.hasPrefix("#") {
                sections.append(line)
            } else if line.contains("```") {
                codeBlocks += 1
            }
            // Extract links [text](url)
            extractMatches(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, from: line).forEach { links.append($0) }
            // Extract images ![alt](url)
            extractMatches(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#, from: line).forEach { images.append($0) }
        }

        var output = ["## Document Structure"]
        output.append("Headings (\(sections.count)):"); sections.forEach { output.append("  \($0)") }
        output.append("Links (\(links.count)):"); links.prefix(20).forEach { output.append("  \($0)") }
        output.append("Images (\(images.count)):"); images.prefix(10).forEach { output.append("  \($0)") }
        output.append("Code blocks (fence openers): \(codeBlocks / 2)")
        return ToolResult(toolName: name, success: true, output: output.joined(separator: "\n"))
    }

    private func convertToHTML(markdown: String) -> ToolResult {
        // Simple line-by-line Markdown → HTML conversion
        var html = ""
        var inCode = false
        var inList = false

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("```") { inCode.toggle(); html += inCode ? "<pre><code>" : "</code></pre>\n"; continue }
            if inCode { html += escapeHTML(line) + "\n"; continue }

            var l = line
            // Headings
            for h in stride(from: 6, through: 1, by: -1) {
                let prefix = String(repeating: "#", count: h) + " "
                if l.hasPrefix(prefix) { l = "<h\(h)>\(l.dropFirst(prefix.count))</h\(h)>"; break }
            }
            // Bold/italic
            l = l.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
            l = l.replacingOccurrences(of: #"\*(.+?)\*"#,   with: "<em>$1</em>",           options: .regularExpression)
            // Links
            l = l.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
            html += l + "\n"
        }
        let maxChars = 10_000
        let output = html.count > maxChars ? String(html.prefix(maxChars)) + "\n... [truncated]" : html
        return ToolResult(toolName: name, success: true, output: output)
    }

    private func generateTOC(markdown: String) -> ToolResult {
        let headingRegex = try? NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$", options: .anchorsMatchLines)
        let range = NSRange(markdown.startIndex..., in: markdown)
        let matches = headingRegex?.matches(in: markdown, range: range) ?? []
        var toc: [String] = ["## Table of Contents"]
        for match in matches {
            guard let levelRange = Range(match.range(at: 1), in: markdown),
                  let textRange  = Range(match.range(at: 2), in: markdown) else { continue }
            let level = markdown[levelRange].count
            let text  = String(markdown[textRange])
            let indent = String(repeating: "  ", count: level - 1)
            let anchor = text.lowercased().replacingOccurrences(of: " ", with: "-").filter { $0.isLetter || $0.isNumber || $0 == "-" }
            toc.append("\(indent)- [\(text)](#\(anchor))")
        }
        return ToolResult(toolName: name, success: true, output: toc.joined(separator: "\n"))
    }

    private func countWords(markdown: String) -> ToolResult {
        // Strip code blocks and markdown syntax for accurate word count
        var text = markdown
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "#+ ", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[\\[\\]()!]", with: "", options: .regularExpression)

        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordCount = words.count
        let charCount = text.filter { !$0.isWhitespace }.count
        let readingMinutes = max(1, wordCount / 200)  // average 200 wpm

        return ToolResult(toolName: name, success: true,
                          output: "Words: \(wordCount)\nCharacters (no spaces): \(charCount)\nEstimated reading time: ~\(readingMinutes) min")
    }

    // MARK: - Helpers

    private func loadMarkdown(arguments: [String: ToolArgumentValue]) throws -> String {
        if let content = arguments["content"]?.stringValue { return content }
        guard let rawPath = arguments["path"]?.stringValue else {
            throw ToolError.missingRequiredParameter("path or content")
        }
        let path = NSString(string: rawPath).expandingTildeInPath
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func extractMatches(pattern: String, from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `NSRegularExpression` | Heading, link, and image extraction; markdown element parsing |
| `Foundation` string manipulation | Bold/italic substitution, HTML conversion |

### Key Implementation Steps

1. **structure** — scan lines for `#` headings; use regex for `[text](url)` links and `![alt](url)` images; count ` ``` ` fence openers.
2. **to_html** — a lightweight line-by-line parser covering headings H1–H6, bold/italic, and links. For a complete implementation, consider bundling `cmark` (C library).
3. **toc** — regex to extract heading level and text; slugify the text for anchor links.
4. **word_count** — strip code blocks and markdown syntax, split on whitespace, estimate reading time at 200 WPM.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Read `.md` files under `~` |

---

## Example Tool Calls

```json
{"tool": "markdown", "arguments": {"action": "toc", "path": "~/Documents/README.md"}}
```

```json
{"tool": "markdown", "arguments": {"action": "word_count", "content": "# Hello\n\nThis is a test."}}
```

---

## See Also

- [PDFTool](./PDFTool.md)
- [FileSystemTool](../mlx-testing/AgentTools/FileSystemTool.swift) *(existing)*
