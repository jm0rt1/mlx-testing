# WebScraperTool

**Category:** Developer Productivity
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `web_scraper`

## Overview

`WebScraperTool` fetches web page content and returns it in a readable format. It strips HTML to plain text, extracts links, and can follow paginated pages. Because it makes outbound network requests and can fetch arbitrary URLs, it requires approval. Useful for reading documentation, extracting information from web pages, or summarising articles.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `url` | string | Yes | — | URL to fetch |
| `action` | string | No | `"text"` | One of `text`, `links`, `meta`, `paginate` |
| `max_pages` | integer | No | `1` | Maximum pages to follow for `paginate` (max 5) |
| `css_selector` | string | No | — | CSS selector to extract specific elements |

---

## Swift Implementation

```swift
import Foundation

struct WebScraperTool: AgentTool {

    let name = "web_scraper"
    let toolDescription = "Fetch a web page and return its text content, links, or metadata. Optionally follow paginated links."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "url",          type: .string,  description: "URL to fetch",              required: true),
        ToolParameter(name: "action",       type: .string,  description: "text | links | meta | paginate",
                      required: false, defaultValue: "text",
                      enumValues: ["text", "links", "meta", "paginate"]),
        ToolParameter(name: "max_pages",    type: .integer, description: "Pages to follow (max 5)",   required: false, defaultValue: "1"),
        ToolParameter(name: "css_selector", type: .string,  description: "CSS selector for content extraction", required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let urlString = arguments["url"]?.stringValue else { throw ToolError.missingRequiredParameter("url") }
        guard let url = URL(string: urlString) else {
            return ToolResult(toolName: name, success: false, output: "Invalid URL: \(urlString)")
        }
        let action = arguments["action"]?.stringValue ?? "text"
        let maxPages: Int
        if case .integer(let p) = arguments["max_pages"] { maxPages = min(p, 5) } else { maxPages = 1 }

        switch action {
        case "text":     return try await fetchText(url: url)
        case "links":    return try await fetchLinks(url: url)
        case "meta":     return try await fetchMeta(url: url)
        case "paginate": return try await paginatePages(startURL: url, maxPages: maxPages)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func fetchText(url: URL) async throws -> ToolResult {
        let html = try await fetchHTML(url: url)
        let text = stripHTML(html)
        let maxChars = 8_000
        let output = text.count > maxChars ? String(text.prefix(maxChars)) + "\n... [truncated]" : text
        return ToolResult(toolName: name, success: true, output: output)
    }

    private func fetchLinks(url: URL) async throws -> ToolResult {
        let html = try await fetchHTML(url: url)
        let links = extractLinks(html: html, baseURL: url)
        let output = "Links on \(url):\n" + links.prefix(50).map { "  \($0)" }.joined(separator: "\n")
        return ToolResult(toolName: name, success: true, output: output)
    }

    private func fetchMeta(url: URL) async throws -> ToolResult {
        let html = try await fetchHTML(url: url)
        let title       = extract(pattern: "<title>(.*?)</title>", from: html)
        let description = extractAttribute(tag: "meta", attr: "description", from: html)
        let ogTitle     = extractOGProperty("og:title", from: html)
        var lines = ["URL: \(url)"]
        if let t = title   { lines.append("Title: \(t)") }
        if let d = description { lines.append("Description: \(d)") }
        if let ot = ogTitle   { lines.append("OG Title: \(ot)") }
        return ToolResult(toolName: name, success: true, output: lines.joined(separator: "\n"))
    }

    private func paginatePages(startURL: URL, maxPages: Int) async throws -> ToolResult {
        var results: [String] = []
        var currentURL: URL? = startURL
        var page = 0
        while let url = currentURL, page < maxPages {
            let html = try await fetchHTML(url: url)
            results.append("=== Page \(page + 1): \(url) ===\n" + stripHTML(html).prefix(3_000))
            currentURL = findNextPageLink(html: html, baseURL: url)
            page += 1
        }
        let output = results.joined(separator: "\n\n")
        return ToolResult(toolName: name, success: true,
                          output: output.count > 12_000 ? String(output.prefix(12_000)) + "\n... [truncated]" : output)
    }

    // MARK: - Helpers

    private func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Apple Silicon) MLXCopilot/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func stripHTML(_ html: String) -> String {
        // Remove script and style blocks
        var text = html
        for tag in ["script", "style", "head"] {
            text = text.replacingOccurrences(of: "<\(tag)[^>]*>.*?</\(tag)>",
                                             with: " ", options: [.regularExpression, .caseInsensitive])
        }
        // Remove remaining tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Collapse whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractLinks(html: String, baseURL: URL) -> [String] {
        let pattern = "href=[\"'](https?://[^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[r])
        }
    }

    private func extract(pattern: String, from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    private func extractAttribute(tag: String, attr: String, from html: String) -> String? {
        let pattern = "<\(tag)[^>]+name=[\"']\(attr)[\"'][^>]+content=[\"']([^\"']+)[\"']"
        return extract(pattern: pattern, from: html)
    }

    private func extractOGProperty(_ property: String, from html: String) -> String? {
        let pattern = "<meta[^>]+property=[\"']\(property)[\"'][^>]+content=[\"']([^\"']+)[\"']"
        return extract(pattern: pattern, from: html)
    }

    private func findNextPageLink(html: String, baseURL: URL) -> URL? {
        // Look for rel="next" link
        let pattern = "<a[^>]+rel=[\"']next[\"'][^>]+href=[\"']([^\"']+)[\"']"
        guard let href = extract(pattern: pattern, from: html) else { return nil }
        return URL(string: href) ?? URL(string: href, relativeTo: baseURL)?.absoluteURL
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `URLSession` | Fetch page HTML |
| `NSRegularExpression` | Extract links, title, meta description from raw HTML |
| String manipulation | Strip HTML tags to produce readable plain text |

### Key Implementation Steps

1. **Fetch** — `URLSession.shared.data(for:)` with a 15-second timeout and a browser-like User-Agent.
2. **Strip HTML** — remove `<script>`, `<style>`, and `<head>` blocks first; then strip all remaining tags with a regex; collapse whitespace.
3. **Links** — extract all `href="https://..."` absolute URLs via regex. Cap at 50.
4. **Meta** — extract `<title>`, `<meta name="description" content="...">`, and OG tags.
5. **Paginate** — look for `<a rel="next" href="...">` and follow up to `maxPages` times.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.network.client` | Outbound HTTP (already present) |

---

## Example Tool Calls

```json
{"tool": "web_scraper", "arguments": {"url": "https://swift.org/documentation", "action": "text"}}
```

```json
{"tool": "web_scraper", "arguments": {"url": "https://example.com/blog", "action": "links"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Invalid URL | Returns `"Invalid URL"` |
| Network error | Propagates `URLError` description |
| Non-HTML response (PDF, binary) | Returns truncated raw bytes description |
| JavaScript-rendered pages | Static HTML only; dynamic content loaded via JS is not captured |

---

## Edge Cases

- **JavaScript-heavy SPAs** — only the static HTML is fetched. A WebKit-based approach (`WKWebView`) would be needed for JS-rendered content.
- **Login-required pages** — no cookie/session management; will return the login page instead of content.
- **Encoding** — try UTF-8 first, fall back to ISO-8859-1 for older pages.

---

## See Also

- [HTTPClientTool](./HTTPClientTool.md)
- [WikipediaTool](./WikipediaTool.md)
- [WebSearchTool](./WebSearchTool.md)
