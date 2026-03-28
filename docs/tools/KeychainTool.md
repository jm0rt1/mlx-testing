# KeychainTool

**Category:** macOS System & Hardware
**Risk Level:** high
**Requires Approval:** Yes
**Tool Identifier:** `keychain`

## Overview

`KeychainTool` provides secure storage and retrieval of secrets (passwords, API keys, tokens) using the macOS Keychain. Storing a new secret is `medium` risk; retrieving an existing one is `high` risk (sensitive data exposure) and always requires explicit user approval. Listing key names is safe (values are never revealed). This tool is foundational for other tools like `GitHubTool` and `SlackTool` that need stored credentials.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `save`, `get`, `delete`, `list` |
| `service` | string | No | — | Service label (required for `save`, `get`, `delete`) |
| `account` | string | No | — | Account/username label (required for `save`, `get`, `delete`) |
| `secret` | string | No | — | The secret value to store (required for `save`) |

---

## Swift Implementation

```swift
import Foundation
import Security

struct KeychainTool: AgentTool {

    let name = "keychain"
    let toolDescription = "Securely store, retrieve, and delete secrets in the macOS Keychain. List service names without exposing values."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",  type: .string, description: "save | get | delete | list",
                      required: true, enumValues: ["save", "get", "delete", "list"]),
        ToolParameter(name: "service", type: .string, description: "Service label (e.g. 'github')",         required: false),
        ToolParameter(name: "account", type: .string, description: "Account/username",                      required: false),
        ToolParameter(name: "secret",  type: .string, description: "Secret value (save only, never logged)", required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .high

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        switch action {
        case "save":   return try saveSecret(arguments: arguments)
        case "get":    return try getSecret(arguments: arguments)
        case "delete": return try deleteSecret(arguments: arguments)
        case "list":   return listServices()
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func saveSecret(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let service = arguments["service"]?.stringValue else { throw ToolError.missingRequiredParameter("service") }
        guard let account = arguments["account"]?.stringValue else { throw ToolError.missingRequiredParameter("account") }
        guard let secret  = arguments["secret"]?.stringValue  else { throw ToolError.missingRequiredParameter("secret") }

        guard let data = secret.data(using: .utf8) else {
            throw ToolError.executionFailed("Could not encode secret as UTF-8")
        }

        // Delete existing item first to avoid duplicate item error
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData:   data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            return ToolResult(toolName: name, success: false,
                              output: "Keychain save failed: \(SecCopyErrorMessageString(status, nil) ?? "Unknown error" as CFString)")
        }
        return ToolResult(toolName: name, success: true, output: "Saved secret for service='\(service)' account='\(account)'")
    }

    private func getSecret(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let service = arguments["service"]?.stringValue else { throw ToolError.missingRequiredParameter("service") }
        guard let account = arguments["account"]?.stringValue else { throw ToolError.missingRequiredParameter("account") }

        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            return ToolResult(toolName: name, success: false, output: "Secret not found for service='\(service)' account='\(account)'")
        }
        return ToolResult(toolName: name, success: true, output: secret)
    }

    private func deleteSecret(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let service = arguments["service"]?.stringValue else { throw ToolError.missingRequiredParameter("service") }
        guard let account = arguments["account"]?.stringValue else { throw ToolError.missingRequiredParameter("account") }

        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound {
            return ToolResult(toolName: name, success: false, output: "No item found for service='\(service)' account='\(account)'")
        }
        guard status == errSecSuccess else {
            return ToolResult(toolName: name, success: false, output: "Delete failed: \(status)")
        }
        return ToolResult(toolName: name, success: true, output: "Deleted secret for service='\(service)' account='\(account)'")
    }

    private func listServices() -> ToolResult {
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecReturnAttributes: true,
            kSecMatchLimit:      kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[CFString: Any]] else {
            return ToolResult(toolName: name, success: true, output: "No keychain items stored by this app.")
        }
        let lines = items.compactMap { item -> String? in
            let svc = item[kSecAttrService] as? String ?? "?"
            let acct = item[kSecAttrAccount] as? String ?? "?"
            return "  service='\(svc)'  account='\(acct)'"
        }
        return ToolResult(toolName: name, success: true,
                          output: "Stored secrets (\(lines.count)) — values not shown:\n" + lines.joined(separator: "\n"))
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `Security` framework — `SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete` | Keychain CRUD operations |
| `kSecClassGenericPassword` | Generic password item class (service + account key) |
| `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Accessibility policy: non-exportable, requires unlocked device |

### Key Implementation Steps

1. **Save** — delete any existing item with the same service/account first (to avoid `errSecDuplicateItem`), then call `SecItemAdd` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so the secret cannot be migrated off the device.
2. **Get** — call `SecItemCopyMatching` with `kSecReturnData: true`. Decode the returned `Data` as UTF-8. Never log the secret; return it directly in the `ToolResult.output` string (which is shown to the user in the chat).
3. **Delete** — `SecItemDelete` with service + account query. Handle `errSecItemNotFound` gracefully.
4. **List** — `SecItemCopyMatching` with `kSecReturnAttributes: true` and `kSecMatchLimitAll`. Return only `kSecAttrService` and `kSecAttrAccount` — never `kSecReturnData`.

### Output Truncation

Not applicable; responses are short.

---

## Sandbox Entitlements

The app's keychain access group must be configured in the entitlements. By default, a sandboxed app can access only its own keychain items (using the app's bundle identifier as the access group). No additional entitlement is needed beyond the existing sandbox entitlement.

---

## Example Tool Calls

```json
{"tool": "keychain", "arguments": {"action": "save", "service": "github", "account": "token", "secret": "ghp_..."}}
```

```json
{"tool": "keychain", "arguments": {"action": "get", "service": "github", "account": "token"}}
```

```json
{"tool": "keychain", "arguments": {"action": "list"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| `errSecItemNotFound` on `get` | Returns `success: false` with human-readable message |
| `errSecUserCanceled` | Returns `success: false` with `"User cancelled Keychain access"` |
| Non-UTF-8 secret on `get` | Returns `success: false` with `"Secret is binary data, not text"` |
| Empty `secret` on `save` | Allowed; stores an empty string (useful to clear a value without deleting) |

---

## Edge Cases

- **Cross-process access** — items stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` are only readable by the app that created them. Other apps (e.g., a CLI tool) cannot read them.
- **iCloud Keychain sync** — using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` disables iCloud sync. Use `kSecAttrAccessibleAfterFirstUnlock` if sync is desired.
- **Biometric protection** — add `kSecAccessControlBiometryAny` via `SecAccessControlCreateWithFlags` to require Touch ID / password before `get`.

---

## See Also

- [EncryptionTool](./EncryptionTool.md)
- [VaultTool](./VaultTool.md)
- [GitHubTool](./GitHubTool.md)
