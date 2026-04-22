# ImageProcessingTool

**Category:** Files & Documents
**Risk Level:** medium
**Requires Approval:** Yes (for write operations)
**Tool Identifier:** `image_processing`

## Overview

`ImageProcessingTool` inspects, resizes, converts, and filters images using Core Image and `NSImage`/`CGImage`. Read operations (`info`) are low risk. Write operations (`resize`, `convert`, `filter`, `strip_exif`) create new files and require approval.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `info`, `resize`, `convert`, `filter`, `strip_exif` |
| `path` | string | Yes | — | Input image file path |
| `output_path` | string | No | — | Output file path (defaults to overwriting with same name + `_out`) |
| `max_width` | integer | No | — | Max width in pixels (for `resize`; height is auto-calculated) |
| `max_height` | integer | No | — | Max height in pixels (for `resize`) |
| `format` | string | No | `"jpeg"` | Output format: `jpeg`, `png`, `heic`, `tiff` |
| `filter_name` | string | No | — | Core Image filter: `grayscale`, `blur`, `sharpen`, `auto_enhance` |

---

## Swift Implementation

```swift
import Foundation
import AppKit
import CoreImage

struct ImageProcessingTool: AgentTool {

    let name = "image_processing"
    let toolDescription = "Inspect, resize, convert, and filter images using Core Image."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",      type: .string, description: "info | resize | convert | filter | strip_exif",
                      required: true, enumValues: ["info", "resize", "convert", "filter", "strip_exif"]),
        ToolParameter(name: "path",        type: .string,  description: "Input image path",    required: true),
        ToolParameter(name: "output_path", type: .string,  description: "Output image path",   required: false),
        ToolParameter(name: "max_width",   type: .integer, description: "Max width in pixels", required: false),
        ToolParameter(name: "max_height",  type: .integer, description: "Max height",          required: false),
        ToolParameter(name: "format",      type: .string,  description: "jpeg|png|heic|tiff",  required: false, defaultValue: "jpeg"),
        ToolParameter(name: "filter_name", type: .string,  description: "grayscale|blur|sharpen|auto_enhance", required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action  = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }
        guard let rawPath = arguments["path"]?.stringValue   else { throw ToolError.missingRequiredParameter("path") }
        let path = NSString(string: rawPath).expandingTildeInPath

        switch action {
        case "info":       return imageInfo(path: path)
        case "resize":     return try resize(path: path, arguments: arguments)
        case "convert":    return try convert(path: path, arguments: arguments)
        case "filter":     return try applyFilter(path: path, arguments: arguments)
        case "strip_exif": return try stripEXIF(path: path, arguments: arguments)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func imageInfo(path: String) -> ToolResult {
        guard let image = NSImage(contentsOfFile: path) else {
            return ToolResult(toolName: name, success: false, output: "Cannot load image: \(path)")
        }
        let size = image.size
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let fileSize = attrs?[.size] as? Int ?? 0
        let ext = (path as NSString).pathExtension.uppercased()
        return ToolResult(toolName: name, success: true,
                          output: "File: \(path)\nFormat: \(ext)\nDimensions: \(Int(size.width))×\(Int(size.height)) pts\nFile size: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))")
    }

    private func resize(path: String, arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let image = NSImage(contentsOfFile: path) else {
            return ToolResult(toolName: name, success: false, output: "Cannot load image: \(path)")
        }
        let origSize = image.size
        var newWidth  = origSize.width
        var newHeight = origSize.height

        if case .integer(let mw) = arguments["max_width"]  { newWidth  = min(origSize.width,  CGFloat(mw)) }
        if case .integer(let mh) = arguments["max_height"] { newHeight = min(origSize.height, CGFloat(mh)) }

        // Preserve aspect ratio
        let scale = min(newWidth / origSize.width, newHeight / origSize.height)
        let targetSize = CGSize(width: origSize.width * scale, height: origSize.height * scale)

        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: origSize),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()

        let outPath = outputPath(arguments: arguments, inputPath: path, suffix: "_resized")
        return try save(image: resized, to: outPath, format: arguments["format"]?.stringValue ?? "jpeg")
    }

    private func convert(path: String, arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let image = NSImage(contentsOfFile: path) else {
            return ToolResult(toolName: name, success: false, output: "Cannot load image: \(path)")
        }
        let format = arguments["format"]?.stringValue ?? "jpeg"
        let outPath = outputPath(arguments: arguments, inputPath: path, suffix: "_converted", ext: format)
        return try save(image: image, to: outPath, format: format)
    }

    private func applyFilter(path: String, arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let filterName = arguments["filter_name"]?.stringValue else {
            throw ToolError.missingRequiredParameter("filter_name")
        }
        guard let inputImage = CIImage(contentsOf: URL(fileURLWithPath: path)) else {
            return ToolResult(toolName: name, success: false, output: "Cannot load image: \(path)")
        }

        let ciFilter: CIFilter?
        switch filterName {
        case "grayscale":    ciFilter = CIFilter(name: "CIColorMonochrome", parameters: ["inputColor": CIColor.gray, "inputIntensity": 1.0])
        case "blur":         ciFilter = CIFilter(name: "CIGaussianBlur",    parameters: ["inputRadius": 5.0])
        case "sharpen":      ciFilter = CIFilter(name: "CISharpenLuminance", parameters: ["inputSharpness": 0.7])
        case "auto_enhance":
            let filters = inputImage.autoAdjustmentFilters()
            var img = inputImage
            for f in filters { f.setValue(img, forKey: kCIInputImageKey); img = f.outputImage ?? img }
            let ctx = CIContext()
            let outPath = outputPath(arguments: arguments, inputPath: path, suffix: "_\(filterName)")
            if let cgImg = ctx.createCGImage(img, from: img.extent) {
                return try saveCGImage(cgImg, to: outPath, format: arguments["format"]?.stringValue ?? "jpeg")
            }
            return ToolResult(toolName: name, success: false, output: "Filter rendering failed")
        default:
            throw ToolError.executionFailed("Unknown filter: \(filterName). Use: grayscale, blur, sharpen, auto_enhance")
        }

        ciFilter?.setValue(inputImage, forKey: kCIInputImageKey)
        guard let outputImage = ciFilter?.outputImage else {
            return ToolResult(toolName: name, success: false, output: "Filter produced no output")
        }
        let ctx = CIContext()
        let outPath = outputPath(arguments: arguments, inputPath: path, suffix: "_\(filterName)")
        if let cgImg = ctx.createCGImage(outputImage, from: outputImage.extent) {
            return try saveCGImage(cgImg, to: outPath, format: arguments["format"]?.stringValue ?? "jpeg")
        }
        return ToolResult(toolName: name, success: false, output: "Could not render filtered image")
    }

    private func stripEXIF(path: String, arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        // Re-save without EXIF: CGImageDestinationCopyImageSource without kCGImageDestinationMetadata
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let type = CGImageSourceGetType(src) else {
            return ToolResult(toolName: name, success: false, output: "Cannot read image source: \(path)")
        }
        let outPath = outputPath(arguments: arguments, inputPath: path, suffix: "_noexif")
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, type, 1, nil)!
        let opts: [CFString: Any] = [kCGImageDestinationMetadata: NSNull()]
        CGImageDestinationAddImageFromSource(dest, src, 0, opts as CFDictionary)
        CGImageDestinationFinalize(dest)
        return ToolResult(toolName: name, success: true, output: "EXIF stripped. Saved to \(outPath)",
                          artifacts: [ToolArtifact(type: .filePath, label: "Cleaned image", value: outPath)])
    }

    // MARK: - Helpers

    private func outputPath(arguments: [String: ToolArgumentValue], inputPath: String, suffix: String, ext: String? = nil) -> String {
        if let raw = arguments["output_path"]?.stringValue { return NSString(string: raw).expandingTildeInPath }
        let base = (inputPath as NSString).deletingPathExtension + suffix
        let e = ext ?? (inputPath as NSString).pathExtension
        return base + (e.isEmpty ? "" : "." + e)
    }

    private func save(image: NSImage, to path: String, format: String) throws -> ToolResult {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return ToolResult(toolName: name, success: false, output: "Cannot convert image")
        }
        let fileType: NSBitmapImageRep.FileType
        switch format {
        case "png":  fileType = .png
        case "tiff": fileType = .tiff
        default:     fileType = .jpeg
        }
        guard let data = bitmap.representation(using: fileType, properties: [:]) else {
            return ToolResult(toolName: name, success: false, output: "Cannot encode image as \(format)")
        }
        try data.write(to: URL(fileURLWithPath: path))
        return ToolResult(toolName: name, success: true, output: "Saved \(path)",
                          artifacts: [ToolArtifact(type: .filePath, label: "Image", value: path)])
    }

    private func saveCGImage(_ cgImage: CGImage, to path: String, format: String) throws -> ToolResult {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let fileType: NSBitmapImageRep.FileType = format == "png" ? .png : .jpeg
        guard let data = rep.representation(using: fileType, properties: [:]) else {
            return ToolResult(toolName: name, success: false, output: "Cannot encode filtered image")
        }
        try data.write(to: URL(fileURLWithPath: path))
        return ToolResult(toolName: name, success: true, output: "Saved filtered image to \(path)",
                          artifacts: [ToolArtifact(type: .filePath, label: "Filtered image", value: path)])
    }
}
```

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.files.user-selected.read-write` | Access user-selected image files |
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Access images under `~` |

---

## Example Tool Calls

```json
{"tool": "image_processing", "arguments": {"action": "info", "path": "~/Photos/vacation.jpg"}}
```

```json
{"tool": "image_processing", "arguments": {"action": "resize", "path": "~/photo.jpg", "max_width": 800, "output_path": "~/photo_small.jpg"}}
```

---

## See Also

- [OCRTool](./OCRTool.md)
- [QRCodeTool](./QRCodeTool.md)
