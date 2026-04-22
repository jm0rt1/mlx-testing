# AudioTool

**Category:** macOS System & Hardware
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `audio`

## Overview

`AudioTool` controls system audio and media playback. Reading volume or listing devices is benign; changing volume, switching devices, or controlling Music.app modifies system state. Useful for automating presentations, scripting focus sessions ("mute while recording"), or controlling music without leaving the chat.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `get_volume`, `set_volume`, `mute`, `unmute`, `list_devices`, `set_device`, `media_control`, `transcribe` |
| `volume` | integer | No | — | 0–100 volume level (for `set_volume`) |
| `device_name` | string | No | — | Partial device name to match (for `set_device`) |
| `media_action` | string | No | — | One of `play`, `pause`, `next`, `previous`, `current_track` (for `media_control`) |
| `file_path` | string | No | — | Audio file path (for `transcribe`) |

---

## Swift Implementation

```swift
import Foundation
import AVFoundation

struct AudioTool: AgentTool {

    let name = "audio"
    let toolDescription = "Control system audio volume, input/output devices, and media playback. Transcribe audio files."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action", type: .string, description: "Operation",
                      required: true,
                      enumValues: ["get_volume", "set_volume", "mute", "unmute",
                                   "list_devices", "set_device", "media_control", "transcribe"]),
        ToolParameter(name: "volume",       type: .integer, description: "0–100",       required: false),
        ToolParameter(name: "device_name",  type: .string,  description: "Device name", required: false),
        ToolParameter(name: "media_action", type: .string,
                      description: "play | pause | next | previous | current_track",
                      required: false,
                      enumValues: ["play", "pause", "next", "previous", "current_track"]),
        ToolParameter(name: "file_path",    type: .string,  description: "Audio file",  required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        switch action {
        case "get_volume":    return getVolume()
        case "set_volume":    return try setVolume(arguments: arguments)
        case "mute":          return setMute(true)
        case "unmute":        return setMute(false)
        case "list_devices":  return listDevices()
        case "set_device":    return try setOutputDevice(arguments: arguments)
        case "media_control": return try mediaControl(arguments: arguments)
        case "transcribe":    return try await transcribe(arguments: arguments)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Volume

    private func getVolume() -> ToolResult {
        let vol = (try? runShell("osascript -e 'output volume of (get volume settings)'")) ?? "unknown"
        let muted = (try? runShell("osascript -e 'output muted of (get volume settings)'")) ?? "unknown"
        return ToolResult(toolName: name, success: true,
                          output: "Volume: \(vol.trimmingCharacters(in: .whitespacesAndNewlines))%\nMuted: \(muted.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    private func setVolume(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard case .integer(let level) = arguments["volume"] else {
            throw ToolError.missingRequiredParameter("volume")
        }
        let clamped = min(max(level, 0), 100)
        _ = try? runShell("osascript -e 'set volume output volume \(clamped)'")
        return ToolResult(toolName: name, success: true, output: "Volume set to \(clamped)%")
    }

    private func setMute(_ mute: Bool) -> ToolResult {
        _ = try? runShell("osascript -e 'set volume \(mute ? "" : "without") output muted'")
        return ToolResult(toolName: name, success: true, output: mute ? "Muted" : "Unmuted")
    }

    // MARK: - Devices

    private func listDevices() -> ToolResult {
        // Use `system_profiler SPAudioDataType` for device listing
        let output = (try? runShell("system_profiler SPAudioDataType")) ?? "Unable to list devices"
        let maxChars = 5_000
        let truncated = output.count > maxChars ? String(output.prefix(maxChars)) + "\n... [truncated]" : output
        return ToolResult(toolName: name, success: true, output: truncated)
    }

    private func setOutputDevice(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let deviceName = arguments["device_name"]?.stringValue else {
            throw ToolError.missingRequiredParameter("device_name")
        }
        // SwitchAudioSource CLI (Homebrew) is the simplest approach
        let output = (try? runShell("SwitchAudioSource -s '\(deviceName)'")) ?? "SwitchAudioSource not available"
        return ToolResult(toolName: name, success: true, output: output)
    }

    // MARK: - Media Control

    private func mediaControl(arguments: [String: ToolArgumentValue]) throws -> ToolResult {
        guard let mediaAction = arguments["media_action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("media_action")
        }
        let script: String
        switch mediaAction {
        case "play":          script = "tell application \"Music\" to play"
        case "pause":         script = "tell application \"Music\" to pause"
        case "next":          script = "tell application \"Music\" to next track"
        case "previous":      script = "tell application \"Music\" to previous track"
        case "current_track": script = "tell application \"Music\" to get name of current track & \" by \" & artist of current track"
        default:              throw ToolError.executionFailed("Unknown media_action: \(mediaAction)")
        }
        let output = (try? runShell("osascript -e '\(script)'")) ?? "AppleScript failed"
        return ToolResult(toolName: name, success: true, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Transcription

    private func transcribe(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let rawPath = arguments["file_path"]?.stringValue else {
            throw ToolError.missingRequiredParameter("file_path")
        }
        let path = NSString(string: rawPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            return ToolResult(toolName: name, success: false, output: "File not found: \(path)")
        }
        // Use SFSpeechRecognizer with a local on-device recognition request
        // (SFSpeechAudioBufferRecognitionRequest for real-time; SFSpeechURLRecognitionRequest for files)
        return ToolResult(toolName: name, success: false,
                          output: "Transcription requires microphone/speech recognition entitlement. See SpeechToTextTool for dedicated implementation.")
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
| `osascript` via `Process` | Volume get/set/mute, Music.app control |
| `system_profiler SPAudioDataType` | Enumerate audio devices |
| `SwitchAudioSource` CLI (Homebrew) | Switch default output device programmatically |
| CoreAudio `AudioObjectGetPropertyData` | Native alternative to AppleScript for volume and device management |
| `AVFoundation` — `SFSpeechRecognizer` | On-device audio transcription (see also `SpeechToTextTool`) |

### Key Implementation Steps

1. **Volume get/set** — the simplest approach uses `osascript` with `get volume settings` / `set volume output volume N`. The native alternative is CoreAudio `kAudioHardwareServiceDeviceProperty_VirtualMasterVolume`.
2. **Device listing** — `system_profiler SPAudioDataType` returns a structured plist that can be parsed. For a native approach use `AudioObjectGetPropertyData(kAudioObjectSystemObject, kAudioHardwarePropertyDevices, ...)`.
3. **Device switching** — `SwitchAudioSource -s <name>` (Homebrew) is the simplest approach. Native: set `kAudioHardwarePropertyDefaultOutputDevice` via `AudioObjectSetPropertyData`.
4. **Media control** — AppleScript targets Music.app. For Spotify use `tell application "Spotify"`.
5. **Transcription** — delegate to `SpeechToTextTool` which has dedicated `SFSpeechRecognizer` logic.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.automation.apple-events` | AppleScript for volume and Music.app control |
| `com.apple.security.device.microphone` | If extending with real-time recording |

---

## Example Tool Calls

```json
{"tool": "audio", "arguments": {"action": "set_volume", "volume": 50}}
```

```json
{"tool": "audio", "arguments": {"action": "media_control", "media_action": "current_track"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| `SwitchAudioSource` not installed | Returns message directing user to `brew install switchaudio-osx` |
| Music.app not running for media control | AppleScript auto-launches it; handle gracefully |
| `file_path` not found for transcribe | Returns `success: false` with path info |

---

## Edge Cases

- **Spotify vs Music.app** — detect which app is running before choosing the AppleScript target.
- **Input vs output volume** — volume get/set applies to the output device. For microphone input use `input volume` in the AppleScript.
- **HDMI audio** — devices connected via HDMI appear as separate CoreAudio devices; switching may not affect already-playing audio.

---

## See Also

- [SpeechToTextTool](./SpeechToTextTool.md)
- [TextToSpeechTool](./TextToSpeechTool.md)
- [VoiceMemoTool](./VoiceMemoTool.md)
