# HTTPClientTool

**Category:** Developer Productivity
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `http`

## Overview

`HTTPClientTool` makes HTTP/REST API calls with configurable method, headers, and body. It supports JSON response parsing and returns a formatted summary. Because it can send data to arbitrary external services, it requires approval. Useful for testing APIs, webhooks, or fetching data from any HTTP endpoint.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `url` | string | Yes | — | Full URL including scheme |
| `method` | string | No | `"GET"` | HTTP method: `GET`, `POST`, `PUT`, `PATCH`, `DELETE` |
| `headers` | string | No | — | JSON object of request headers, e.g. `{"Authorization":"Bearer tok"}` |
| `body` | string | No | — | Request body string (for `POST`, `PUT`, `PATCH`) |
| `timeout` | integer | No | `10` | Request timeout in seconds (max 60) |

---

## Swift Implementation

```swift
import Foundation

struct HTTPClientTool: AgentTool {

    let name = "http"
    let toolDescription = "Make HTTP requests (GET, POST, PUT, PATCH, DELETE) with custom headers and body. Returns status code and response body."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "url",     type: .string,  description: "Request URL",              required: true),
        ToolParameter(name: "method",  type: .string,  description: "GET | POST | PUT | PATCH | DELETE",
                      required: false, defaultValue: "GET",
                      enumValues: ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"]),
        ToolParameter(name: "headers", type: .string,  description: "JSON object of headers",   required: false),
        ToolParameter(name: "body",    type: .string,  description: "Request body",             required: false),
        ToolParameter(name: "timeout", type: .integer, description: "Timeout seconds (max 60)", required: false, defaultValue: "10"),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let urlString = arguments["url"]?.stringValue else { throw ToolError.missingRequiredParameter("url") }
        guard let url = URL(string: urlString) else {
            return ToolResult(toolName: name, success: false, output: "Invalid URL: \(urlString)")
        }

        let method  = arguments["method"]?.stringValue ?? "GET"
        let timeout: TimeInterval
        if case .integer(let t) = arguments["timeout"] { timeout = min(Double(t), 60) } else { timeout = 10 }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method

        // Parse headers
        if let headersStr = arguments["headers"]?.stringValue,
           let headersData = headersStr.data(using: .utf8),
           let headersDict = try? JSONSerialization.jsonObject(with: headersData) as? [String: String] {
            headersDict.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        }

        // Set body
        if let bodyStr = arguments["body"]?.stringValue {
            request.httpBody = bodyStr.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        let contentType = httpResponse?.value(forHTTPHeaderField: "Content-Type") ?? ""

        var bodyOutput: String
        if contentType.contains("json"),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            bodyOutput = prettyString
        } else {
            bodyOutput = String(data: data, encoding: .utf8) ?? "(binary response)"
        }

        let maxChars = 8_000
        if bodyOutput.count > maxChars { bodyOutput = String(bodyOutput.prefix(maxChars)) + "\n... [truncated]" }

        let output = "HTTP \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode))\n" +
                     "Content-Type: \(contentType)\n" +
                     "Body (\(data.count) bytes):\n\(bodyOutput)"

        return ToolResult(toolName: name, success: (200..<300).contains(statusCode), output: output)
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `URLSession.shared` | Async HTTP client via `data(for:)` |
| `JSONSerialization` | Pretty-print JSON responses |

### Key Implementation Steps

1. **URL validation** — construct `URL(string:)` and return early if invalid.
2. **Headers** — parse the `headers` parameter as a JSON string into a `[String: String]` dictionary, then set each header on the request.
3. **Body** — set `httpBody` from the `body` parameter as UTF-8 data. Default `Content-Type` to `application/json` if not set.
4. **Response** — use `URLSession.shared.data(for:)` with the configured timeout. Extract status code and `Content-Type`.
5. **JSON pretty-print** — if `Content-Type` contains `"json"`, parse and re-serialise with `.prettyPrinted` for readability.

### Output Truncation

`maxChars = 8_000` on the body output.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.network.client` | Required for outbound HTTP (already present in `mlx_testing.entitlements`) |

---

## Example Tool Calls

```json
{"tool": "http", "arguments": {"url": "https://api.github.com/repos/apple/swift", "method": "GET"}}
```

```json
{"tool": "http", "arguments": {"url": "https://httpbin.org/post", "method": "POST", "body": "{\"key\":\"value\"}", "headers": "{\"X-Custom\":\"header\"}"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Invalid URL | Returns `success: false` with `"Invalid URL"` |
| Network timeout | `URLSession` throws `URLError.timedOut`; return error description |
| Non-2xx status | Returns `success: false` with the status code and body |
| Binary response | Returns `"(binary response)"` placeholder |

---

## Edge Cases

- **Self-signed TLS** — `URLSession` will reject invalid certificates by default. Add a `URLSessionDelegate` with custom `didReceive challenge` handling if needed.
- **Redirects** — `URLSession` follows redirects automatically (up to 5 by default).
- **Large responses** — streaming large binary responses should use `URLSession.bytes(for:)` instead of `data(for:)`.

---

## See Also

- [WebScraperTool](./WebScraperTool.md)
- [WebhookTool](./WebhookTool.md)
- [GitHubTool](./GitHubTool.md)
