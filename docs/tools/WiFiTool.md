# WiFiTool

**Category:** macOS System & Hardware
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `wifi`

## Overview

`WiFiTool` reports wireless network status and diagnostics. It is entirely read-only: it cannot join or leave networks (that would require `medium` risk and approval). Useful for answering "am I on WiFi?" "what's my external IP?" or debugging connectivity issues in an automated script.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `status`, `scan`, `external_ip`, `ping`, `dns` |
| `host` | string | No | `8.8.8.8` | Hostname or IP to ping (for `ping`) |
| `count` | integer | No | `4` | Number of ping packets |

---

## Swift Implementation

```swift
import Foundation
import CoreWLAN

struct WiFiTool: AgentTool {

    let name = "wifi"
    let toolDescription = "Inspect wireless network status, scan for networks, get external IP, and ping hosts."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action", type: .string,
                      description: "Operation to perform",
                      required: true,
                      enumValues: ["status", "scan", "external_ip", "ping", "dns"]),
        ToolParameter(name: "host",  type: .string,  description: "Host to ping",     required: false, defaultValue: "8.8.8.8"),
        ToolParameter(name: "count", type: .integer, description: "Ping packet count", required: false, defaultValue: "4"),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        switch action {
        case "status":      return currentStatus()
        case "scan":        return try scanNetworks()
        case "external_ip": return await getExternalIP()
        case "ping":        return try pingHost(arguments: arguments)
        case "dns":         return getDNS()
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func currentStatus() -> ToolResult {
        guard let iface = CWWiFiClient.shared().interface() else {
            return ToolResult(toolName: name, success: false, output: "No WiFi interface found.")
        }
        var lines = ["## WiFi Status"]
        lines.append("Interface: \(iface.interfaceName ?? "unknown")")
        if let ssid = iface.ssid() {
            lines.append("SSID: \(ssid)")
        } else {
            lines.append("SSID: (not connected)")
        }
        if let bssid = iface.bssid() { lines.append("BSSID: \(bssid)") }
        lines.append("RSSI: \(iface.rssiValue()) dBm")
        lines.append("Noise: \(iface.noiseMeasurement()) dBm")
        if let channel = iface.wlanChannel() {
            lines.append("Channel: \(channel.channelNumber) (\(channel.channelBand == .band5GHz ? "5 GHz" : "2.4 GHz"))")
        }
        lines.append("Transmit rate: \(iface.transmitRate()) Mbps")
        return ToolResult(toolName: name, success: true, output: lines.joined(separator: "\n"))
    }

    private func scanNetworks() throws -> ToolResult {
        guard let iface = CWWiFiClient.shared().interface() else {
            return ToolResult(toolName: name, success: false, output: "No WiFi interface.")
        }
        let networks = (try? iface.scanForNetworks(withName: nil)) ?? []
        let lines = networks.sorted { ($0.rssiValue) > ($1.rssiValue) }.prefix(20).map { n in
            "  \(n.ssid ?? "(hidden)") — \(n.rssiValue) dBm  \(n.security == .none ? "open" : "secured")"
        }
        return ToolResult(toolName: name, success: true,
                          output: "Nearby networks (\(networks.count) found, showing top 20):\n" + lines.joined(separator: "\n"))
    }

    private func getExternalIP() async -> ToolResult {
        guard let url = URL(string: "https://api.ipify.org") else {
            return ToolResult(toolName: name, success: false, output: "Invalid URL")
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let ip = String(data: data, encoding: .utf8) else {
            return ToolResult(toolName: name, success: false, output: "Could not reach external IP service")
        }
        return ToolResult(toolName: name, success: true, output: "External IP: \(ip)")
    }

    private func pingHost(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        let host  = arguments["host"]?.stringValue ?? "8.8.8.8"
        let count: Int
        if case .integer(let c) = arguments["count"] { count = min(c, 10) } else { count = 4 }
        let output = (try? runShell("ping -c \(count) \(host)")) ?? "ping failed"
        let maxChars = 3_000
        let truncated = output.count > maxChars ? String(output.prefix(maxChars)) + "\n... [truncated]" : output
        return ToolResult(toolName: name, success: true, output: truncated)
    }

    private func getDNS() -> ToolResult {
        let output = (try? runShell("scutil --dns | head -20")) ?? "scutil not available"
        return ToolResult(toolName: name, success: true, output: output)
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
| `CoreWLAN` — `CWWiFiClient`, `CWInterface` | Current SSID, BSSID, RSSI, channel, scan for nearby networks |
| `URLSession` | Fetch external IP from `api.ipify.org` |
| `ping` system binary | ICMP round-trip time measurement |
| `scutil --dns` | Current DNS server configuration |

### Key Implementation Steps

1. **Status** — `CWWiFiClient.shared().interface()` returns the primary WiFi interface. Read `ssid()`, `rssiValue()`, `noiseMeasurement()`, `wlanChannel()`, `transmitRate()`.
2. **Scan** — `iface.scanForNetworks(withName: nil)` returns a `Set<CWNetwork>`. Sort by RSSI descending and cap at 20 results.
3. **External IP** — `GET https://api.ipify.org` returns the raw public IP as plain text.
4. **Ping** — shell out to `/sbin/ping -c <count> <host>`. Cap at 10 packets. Truncate output at 3,000 characters.
5. **DNS** — `scutil --dns` returns the current DNS resolver configuration. Pipe through `head -20`.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.network.client` | HTTP request to `api.ipify.org` for external IP (already present) |

`CoreWLAN` scanning and `ping` work within the standard sandbox.

---

## Example Tool Calls

```json
{"tool": "wifi", "arguments": {"action": "status"}}
```

```json
{"tool": "wifi", "arguments": {"action": "ping", "host": "google.com", "count": 3}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| No WiFi interface (Ethernet-only Mac) | Returns `"No WiFi interface found"` |
| External IP service unreachable | Returns `"Could not reach external IP service"` |
| `ping` host unreachable | Returns shell output including `"Request timeout"` lines |

---

## Edge Cases

- **VPN active** — external IP will reflect the VPN exit node, not the home router IP.
- **Network scan requires Location Services** — macOS 10.15+ requires Location permission for `scanForNetworks`. Add a note if the permission is denied.
- **Ethernet only** — `CWWiFiClient.shared().interface()` returns `nil`; return graceful message.

---

## See Also

- [NetworkScannerTool](./NetworkScannerTool.md)
- [CertificateInspectorTool](./CertificateInspectorTool.md)
- [SystemInfoTool](./SystemInfoTool.md)
