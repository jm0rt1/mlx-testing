# PhotosTool

**Category:** Productivity & Personal Data
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `photos`

## Overview

`PhotosTool` browses and exports from the Photos library via `PhotoKit`. Listing albums and searching for assets is read-only; exporting photos to temporary files accesses the photo library and requires approval.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list_albums`, `search`, `export`, `metadata` |
| `album_name` | string | No | — | Album name filter (for `list_albums`) |
| `query` | string | No | — | Search term: date range, place, or keyword |
| `asset_id` | string | No | — | Asset local identifier (for `export`, `metadata`) |
| `output_path` | string | No | `~/Desktop/exported_photo.jpg` | Export destination |

---

## Swift Implementation

```swift
import Foundation
import Photos

struct PhotosTool: AgentTool {

    let name = "photos"
    let toolDescription = "Browse and export photos from the Photos library using PhotoKit."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",      type: .string, description: "list_albums | search | export | metadata",
                      required: true, enumValues: ["list_albums", "search", "export", "metadata"]),
        ToolParameter(name: "album_name",  type: .string,  description: "Album name filter",     required: false),
        ToolParameter(name: "query",       type: .string,  description: "Search / date / place", required: false),
        ToolParameter(name: "asset_id",    type: .string,  description: "Asset local identifier",required: false),
        ToolParameter(name: "output_path", type: .string,  description: "Export path",           required: false, defaultValue: "~/Desktop/photo.jpg"),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }

        let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authStatus == .denied || authStatus == .restricted {
            return ToolResult(toolName: name, success: false,
                              output: "Photos access denied. Enable in System Settings > Privacy & Security > Photos.")
        }
        if authStatus == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }

        switch action {
        case "list_albums": return listAlbums(filter: arguments["album_name"]?.stringValue)
        case "search":      return searchAssets(query: arguments["query"]?.stringValue ?? "")
        case "export":      return try await exportAsset(arguments: arguments)
        case "metadata":    return assetMetadata(arguments: arguments)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func listAlbums(filter: String?) -> ToolResult {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        var lines: [String] = []
        albums.enumerateObjects { collection, _, _ in
            if let f = filter, !collection.localizedTitle.flatMap({ $0.localizedCaseInsensitiveContains(f) ? true : nil }) ?? false { return }
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            lines.append("  • \(collection.localizedTitle ?? "Untitled") (\(count) items)")
        }
        return ToolResult(toolName: name, success: true,
                          output: "Albums (\(lines.count)):\n" + (lines.isEmpty ? "(none)" : lines.joined(separator: "\n")))
    }

    private func searchAssets(query: String) -> ToolResult {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 20
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var lines: [String] = []
        let df = DateFormatter(); df.dateStyle = .short
        assets.enumerateObjects { asset, _, _ in
            let date = asset.creationDate.map { df.string(from: $0) } ?? "?"
            lines.append("  id: \(asset.localIdentifier) | \(date) | \(asset.pixelWidth)×\(asset.pixelHeight)")
        }
        return ToolResult(toolName: name, success: true,
                          output: "Recent photos (\(lines.count)):\n" + lines.joined(separator: "\n"))
    }

    private func exportAsset(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let assetId = arguments["asset_id"]?.stringValue else { throw ToolError.missingRequiredParameter("asset_id") }
        let rawOut = arguments["output_path"]?.stringValue ?? "~/Desktop/photo.jpg"
        let outPath = NSString(string: rawOut).expandingTildeInPath

        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = result.firstObject else {
            return ToolResult(toolName: name, success: false, output: "Asset not found: \(assetId)")
        }

        return await withCheckedContinuation { cont in
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode  = .highQualityFormat
            manager.requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                guard let data else {
                    cont.resume(returning: ToolResult(toolName: "photos", success: false, output: "Could not export asset"))
                    return
                }
                do {
                    try data.write(to: URL(fileURLWithPath: outPath))
                    cont.resume(returning: ToolResult(toolName: "photos", success: true,
                                                       output: "Exported to \(outPath) (\(data.count) bytes)",
                                                       artifacts: [ToolArtifact(type: .filePath, label: "Photo", value: outPath)]))
                } catch {
                    cont.resume(returning: ToolResult(toolName: "photos", success: false, output: "Write error: \(error)"))
                }
            }
        }
    }

    private func assetMetadata(arguments: [String: ToolArgumentValue]) -> ToolResult {
        guard let assetId = arguments["asset_id"]?.stringValue else {
            return ToolResult(toolName: name, success: false, output: "asset_id required for metadata")
        }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = result.firstObject else {
            return ToolResult(toolName: name, success: false, output: "Asset not found: \(assetId)")
        }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .medium
        var lines = [
            "Asset ID: \(asset.localIdentifier)",
            "Dimensions: \(asset.pixelWidth)×\(asset.pixelHeight)",
            "Created: \(asset.creationDate.map { df.string(from: $0) } ?? "?")",
        ]
        if let loc = asset.location {
            lines.append("Location: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
        }
        return ToolResult(toolName: name, success: true, output: lines.joined(separator: "\n"))
    }
}
```

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.personal-information.photos-library` | PHPhotoLibrary access |
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Write exported photos to `~/Desktop` |

---

## Example Tool Calls

```json
{"tool": "photos", "arguments": {"action": "list_albums"}}
```

```json
{"tool": "photos", "arguments": {"action": "export", "asset_id": "A3F2...", "output_path": "~/Desktop/photo.jpg"}}
```

---

## See Also

- [ImageProcessingTool](./ImageProcessingTool.md)
- [OCRTool](./OCRTool.md)
