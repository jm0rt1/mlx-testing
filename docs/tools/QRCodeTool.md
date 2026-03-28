# QRCodeTool

**Category:** Files & Documents
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `qr_code`

## Overview

`QRCodeTool` generates QR codes from strings and decodes QR codes from image files using Core Image. It also generates Code 128 and PDF417 barcodes. Entirely computation-based (no network, no file modification without an explicit output path), this tool is safe for automatic execution.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `generate`, `decode` |
| `content` | string | No | — | Text to encode (for `generate`) |
| `image_path` | string | No | — | Image file containing a barcode (for `decode`) |
| `output_path` | string | No | `~/Desktop/qrcode.png` | Output PNG path (for `generate`) |
| `type` | string | No | `"qr"` | Barcode type: `qr`, `code128`, `pdf417` |
| `scale` | integer | No | `10` | Scale factor for output image (pixels per module) |

---

## Swift Implementation

```swift
import Foundation
import CoreImage
import AppKit
import Vision

struct QRCodeTool: AgentTool {

    let name = "qr_code"
    let toolDescription = "Generate QR codes and barcodes from strings. Decode QR codes and barcodes from image files."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",      type: .string,  description: "generate | decode",
                      required: true, enumValues: ["generate", "decode"]),
        ToolParameter(name: "content",     type: .string,  description: "Text to encode",                          required: false),
        ToolParameter(name: "image_path",  type: .string,  description: "Image file to decode",                    required: false),
        ToolParameter(name: "output_path", type: .string,  description: "Output PNG path",                         required: false, defaultValue: "~/Desktop/qrcode.png"),
        ToolParameter(name: "type",        type: .string,  description: "qr | code128 | pdf417",
                      required: false, defaultValue: "qr", enumValues: ["qr", "code128", "pdf417"]),
        ToolParameter(name: "scale",       type: .integer, description: "Scale factor (pixels per module)",        required: false, defaultValue: "10"),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }

        switch action {
        case "generate": return try generate(arguments: arguments)
        case "decode":   return try decode(arguments: arguments)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Generate

    private func generate(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let content = arguments["content"]?.stringValue else { throw ToolError.missingRequiredParameter("content") }
        let rawOutPath = arguments["output_path"]?.stringValue ?? "~/Desktop/qrcode.png"
        let outPath = NSString(string: rawOutPath).expandingTildeInPath
        let scale: Int
        if case .integer(let s) = arguments["scale"] { scale = min(max(s, 1), 50) } else { scale = 10 }
        let barcodeType = arguments["type"]?.stringValue ?? "qr"

        let filterName: String
        switch barcodeType {
        case "code128": filterName = "CICode128BarcodeGenerator"
        case "pdf417":  filterName = "CIPDF417BarcodeGenerator"
        default:        filterName = "CIQRCodeGenerator"
        }

        guard let filter = CIFilter(name: filterName) else {
            return ToolResult(toolName: name, success: false, output: "Core Image filter not available: \(filterName)")
        }
        filter.setValue(content.data(using: .utf8), forKey: "inputMessage")
        if barcodeType == "qr" { filter.setValue("M", forKey: "inputCorrectionLevel") }

        guard let ciImage = filter.outputImage else {
            return ToolResult(toolName: name, success: false, output: "Could not generate barcode")
        }

        // Scale up
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        let ctx = CIContext()
        guard let cgImage = ctx.createCGImage(scaledImage, from: scaledImage.extent) else {
            return ToolResult(toolName: name, success: false, output: "Could not render barcode to image")
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return ToolResult(toolName: name, success: false, output: "Could not encode PNG")
        }
        try pngData.write(to: URL(fileURLWithPath: outPath))
        return ToolResult(toolName: name, success: true,
                          output: "QR code saved to \(outPath) (\(Int(scaledImage.extent.width))×\(Int(scaledImage.extent.height)) px)",
                          artifacts: [ToolArtifact(type: .filePath, label: "QR Code", value: outPath)])
    }

    // MARK: - Decode

    private func decode(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let rawPath = arguments["image_path"]?.stringValue else { throw ToolError.missingRequiredParameter("image_path") }
        let path = NSString(string: rawPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            return ToolResult(toolName: name, success: false, output: "Image not found: \(path)")
        }

        guard let cgImage = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ToolResult(toolName: name, success: false, output: "Cannot load image: \(path)")
        }

        return await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { req, _ in
                let results = req.results as? [VNBarcodeObservation] ?? []
                if results.isEmpty {
                    continuation.resume(returning: ToolResult(toolName: "qr_code", success: false, output: "No barcodes detected in image"))
                } else {
                    let decoded = results.map { obs in
                        "[\(obs.symbology.rawValue)] \(obs.payloadStringValue ?? "(binary)")"
                    }.joined(separator: "\n")
                    continuation.resume(returning: ToolResult(toolName: "qr_code", success: true,
                                                               output: "Detected \(results.count) barcode(s):\n\(decoded)"))
                }
            }
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        }
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `CoreImage` — `CIQRCodeGenerator`, `CICode128BarcodeGenerator`, `CIPDF417BarcodeGenerator` | Barcode generation |
| `Vision` — `VNDetectBarcodesRequest` | Multi-symbology barcode detection from images |
| `AppKit` — `NSBitmapImageRep` | PNG encoding |

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Write QR code PNG to `~/Desktop` |

---

## Example Tool Calls

```json
{"tool": "qr_code", "arguments": {"action": "generate", "content": "https://example.com", "scale": 15}}
```

```json
{"tool": "qr_code", "arguments": {"action": "decode", "image_path": "~/Downloads/scan.png"}}
```

---

## See Also

- [ImageProcessingTool](./ImageProcessingTool.md)
- [OCRTool](./OCRTool.md)
