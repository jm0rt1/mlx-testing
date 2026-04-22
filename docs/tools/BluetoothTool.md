# BluetoothTool

**Category:** macOS System & Hardware
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `bluetooth`

## Overview

`BluetoothTool` manages Bluetooth device discovery and connections. Listing devices is read-only; connecting or disconnecting changes system state and requires approval. Useful for scripting headphone switching, diagnosing peripheral connectivity, or automating "connect to desk headphones when arriving home."

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list`, `connect`, `disconnect`, `rssi` |
| `device_name` | string | No | — | Partial or full device name (for `connect`, `disconnect`, `rssi`) |
| `device_address` | string | No | — | Bluetooth MAC address (alternative to `device_name`) |

---

## Swift Implementation

```swift
import Foundation
import IOBluetooth

struct BluetoothTool: AgentTool {

    let name = "bluetooth"
    let toolDescription = "List paired Bluetooth devices, connect/disconnect them, and check signal strength."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action", type: .string,
                      description: "Operation to perform",
                      required: true,
                      enumValues: ["list", "connect", "disconnect", "rssi"]),
        ToolParameter(name: "device_name",    type: .string, description: "Partial device name",     required: false),
        ToolParameter(name: "device_address", type: .string, description: "Bluetooth MAC address",   required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        let identifier = arguments["device_name"]?.stringValue ?? arguments["device_address"]?.stringValue

        switch action {
        case "list":       return listDevices()
        case "connect":    return try connectDevice(identifier: identifier)
        case "disconnect": return try disconnectDevice(identifier: identifier)
        case "rssi":       return try getRSSI(identifier: identifier)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func listDevices() -> ToolResult {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return ToolResult(toolName: name, success: true, output: "No paired Bluetooth devices found.")
        }
        let lines = devices.map { d -> String in
            let connected = d.isConnected() ? "✓ connected" : "○ disconnected"
            return "• \(d.nameOrAddress ?? "Unknown") — \(d.addressString ?? "?") [\(connected)]"
        }
        return ToolResult(toolName: name, success: true,
                          output: "Paired Bluetooth devices (\(devices.count)):\n" + lines.joined(separator: "\n"))
    }

    private func connectDevice(identifier: String?) throws -> ToolResult {
        guard let id = identifier else { throw ToolError.missingRequiredParameter("device_name or device_address") }
        guard let device = findDevice(identifier: id) else {
            return ToolResult(toolName: name, success: false, output: "Device not found: \(id)")
        }
        let result = device.openConnection()
        return ToolResult(toolName: name, success: result == kIOReturnSuccess,
                          output: result == kIOReturnSuccess ? "Connected to \(device.nameOrAddress ?? id)" : "Failed to connect (error \(result))")
    }

    private func disconnectDevice(identifier: String?) throws -> ToolResult {
        guard let id = identifier else { throw ToolError.missingRequiredParameter("device_name or device_address") }
        guard let device = findDevice(identifier: id) else {
            return ToolResult(toolName: name, success: false, output: "Device not found: \(id)")
        }
        let result = device.closeConnection()
        return ToolResult(toolName: name, success: result == kIOReturnSuccess,
                          output: result == kIOReturnSuccess ? "Disconnected \(device.nameOrAddress ?? id)" : "Failed to disconnect (error \(result))")
    }

    private func getRSSI(identifier: String?) throws -> ToolResult {
        guard let id = identifier else { throw ToolError.missingRequiredParameter("device_name or device_address") }
        guard let device = findDevice(identifier: id) else {
            return ToolResult(toolName: name, success: false, output: "Device not found: \(id)")
        }
        guard device.isConnected() else {
            return ToolResult(toolName: name, success: false, output: "Device not connected; RSSI unavailable")
        }
        let rssi = device.rawRSSI()
        return ToolResult(toolName: name, success: true,
                          output: "RSSI for \(device.nameOrAddress ?? id): \(rssi) dBm")
    }

    // MARK: - Helper

    private func findDevice(identifier: String) -> IOBluetoothDevice? {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        return devices.first {
            $0.nameOrAddress?.localizedCaseInsensitiveContains(identifier) == true ||
            $0.addressString?.localizedCaseInsensitiveContains(identifier) == true
        }
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `IOBluetooth` | `IOBluetoothDevice.pairedDevices()`, `openConnection()`, `closeConnection()`, `rawRSSI()` |
| `CoreBluetooth` | Alternative for BLE (Bluetooth Low Energy) peripherals via `CBCentralManager` |
| `blueutil` CLI (Homebrew) | Shell-based alternative: `blueutil --paired`, `blueutil --connect <address>` |

### Key Implementation Steps

1. **List** — call `IOBluetoothDevice.pairedDevices()` to get all paired devices. Format each with name, MAC address, and connection state from `isConnected()`.
2. **Connect** — find the `IOBluetoothDevice` by partial name match, then call `openConnection()`. Check return value against `kIOReturnSuccess`.
3. **Disconnect** — call `closeConnection()` on the found device.
4. **RSSI** — only available for connected devices via `rawRSSI()`. Return dBm value.

### Output Truncation

Not applicable; responses are short lists.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.device.bluetooth` | Access to Bluetooth hardware (may require user consent dialog) |

---

## Example Tool Calls

```json
{"tool": "bluetooth", "arguments": {"action": "list"}}
```

```json
{"tool": "bluetooth", "arguments": {"action": "connect", "device_name": "AirPods Pro"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Device not in paired list | Returns `success: false` with `"Device not found"` message |
| `openConnection()` returns error code | Returns the IOKit error code in the output string |
| RSSI requested for disconnected device | Returns `"Device not connected; RSSI unavailable"` |

---

## Edge Cases

- **BLE vs Classic** — `IOBluetooth` only covers Classic Bluetooth (BR/EDR). BLE devices require `CoreBluetooth` with a `CBCentralManager` scan.
- **AirPods** — connect/disconnect cycles affect macOS audio output device; consider triggering `AudioTool.set_device` after connecting.
- **Privacy prompt** — on first use, macOS will display a Bluetooth access permission dialog.

---

## See Also

- [AudioTool](./AudioTool.md)
- [WiFiTool](./WiFiTool.md)
