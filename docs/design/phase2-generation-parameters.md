# Generation Parameters — Milestone 2.4

> Technical design for exposable generation parameter controls (temperature, top-p, max tokens).

**Status:** Ready for implementation
**Milestone:** [2.4 — Generation Parameter Controls](../vision/06-roadmap.md)
**Requirements:** [FR-1.5](../vision/02-requirements.md)

---

## Overview

Currently, generation parameters (temperature, max tokens) are hardcoded in `LocalLLMServiceMLX`. This design exposes them as user-adjustable controls in the toolbar, persisted via `UserDefaults`, so users can tune creativity, length, and sampling behavior.

## Goals

- Expose temperature, top-p, and max tokens as adjustable controls
- Persist settings across app restarts
- Changes take effect on the next generation (no model reload required)
- Provide sensible defaults and clear labeling

## Non-Goals

- Per-conversation parameter overrides (future enhancement)
- Advanced parameters (repetition penalty, min-p, frequency penalty)
- Preset profiles ("Creative", "Precise", "Balanced")

---

## Current State

### What Exists

- `LocalLLMServiceMLX` has a hardcoded `generateParameters`:
  ```swift
  var generateParameters = GenerateParameters(maxTokens: 2048, temperature: 0.6)
  ```
- `GenerateParameters` is an MLX Swift LM type that supports `temperature`, `topP`, `maxTokens`, and more
- The `LLMService` protocol's `generateReplyStreaming()` uses whatever parameters the implementation holds internally

### What's Missing

- No UI to adjust parameters
- No persistence for parameter values
- Parameters are not passed from the ViewModel to the service

---

## Proposed Design

### Data Model

#### `GenerationSettings` (new struct)

```swift
struct GenerationSettings: Codable, Hashable {
    var temperature: Double = 0.6
    var topP: Double = 0.9
    var maxTokens: Int = 2048
    
    // Validation ranges
    static let temperatureRange: ClosedRange<Double> = 0.0...2.0
    static let topPRange: ClosedRange<Double> = 0.0...1.0
    static let maxTokensRange: ClosedRange<Int> = 128...8192
    static let maxTokensStep: Int = 128
    
    static let `default` = GenerationSettings()
}
```

Place in: `mlx-testing/GenerationSettings.swift`

### Storage

| Data | Location | Format |
|---|---|---|
| Generation settings | `UserDefaults` key `"generationSettings"` | JSON-encoded `GenerationSettings` |

**Why UserDefaults:** These are lightweight user preferences (3 numbers). No need for a separate file. The existing pattern uses UserDefaults for `selectedModelID` and `tool_always_approved`.

### LLMService Protocol Change

The `LLMService` protocol's `generateReplyStreaming` method needs to accept generation settings:

```swift
protocol LLMService: AnyObject {
    // ... existing properties ...
    
    func generateReplyStreaming(
        from messages: [ChatMessage],
        systemPrompt: String,
        settings: GenerationSettings,  // New parameter
        onToken: @escaping @MainActor (String) -> Void
    ) async throws
}
```

**Alternative (less invasive):** Instead of changing the protocol, `ChatViewModel` could set a `generationSettings` property on the service before each generation call. This avoids a protocol-breaking change:

```swift
protocol LLMService: AnyObject {
    var generationSettings: GenerationSettings { get set }  // New property
    // ... rest unchanged
}
```

**Recommendation:** Use the property approach. It's less invasive and aligns with how `generateParameters` already works as a mutable property on `LocalLLMServiceMLX`.

### ChatViewModel Changes

```swift
class ChatViewModel: ObservableObject {
    // ... existing properties ...
    
    @Published var generationSettings: GenerationSettings {
        didSet { saveSettings() }
    }
    
    private func saveSettings() {
        if let data = try? JSONEncoder().encode(generationSettings) {
            UserDefaults.standard.set(data, forKey: "generationSettings")
        }
    }
    
    private func loadSettings() -> GenerationSettings {
        guard let data = UserDefaults.standard.data(forKey: "generationSettings"),
              let settings = try? JSONDecoder().decode(GenerationSettings.self, from: data)
        else { return .default }
        return settings
    }
    
    // In send(), before generation:
    // llmService.generationSettings = generationSettings
}
```

### UI Changes

#### Generation Settings Popover

A new toolbar button that shows a settings popover with sliders and a stepper:

```swift
private struct GenerationSettingsView: View {
    @Binding var settings: GenerationSettings
    
    var body: some View {
        Form {
            Section("Sampling") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.2f", settings.temperature))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $settings.temperature,
                        in: GenerationSettings.temperatureRange,
                        step: 0.05
                    )
                    Text("Higher = more creative, lower = more deterministic")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Top-P")
                        Spacer()
                        Text(String(format: "%.2f", settings.topP))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $settings.topP,
                        in: GenerationSettings.topPRange,
                        step: 0.05
                    )
                    Text("Nucleus sampling threshold")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Section("Output") {
                Stepper(
                    "Max Tokens: \(settings.maxTokens)",
                    value: $settings.maxTokens,
                    in: GenerationSettings.maxTokensRange,
                    step: GenerationSettings.maxTokensStep
                )
                Text("Maximum number of tokens in the response")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Section {
                Button("Reset to Defaults") {
                    settings = .default
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 300)
        .padding()
    }
}
```

**Toolbar integration:**
```swift
// In ContentView toolbar:
ToolbarItem {
    Button(action: { showGenerationSettings.toggle() }) {
        Image(systemName: "slider.horizontal.3")
    }
    .popover(isPresented: $showGenerationSettings) {
        GenerationSettingsView(settings: $vm.generationSettings)
    }
}
```

**Design decisions:**
- Popover (not sheet) — lightweight, stays in context, same pattern as the model picker
- Slider step of 0.05 — fine-grained enough for experimentation, not overwhelming
- "Reset to Defaults" button — easy recovery from experimentation
- Private view inside `ContentView.swift` — follows the pattern of other private sub-views

---

## Implementation Plan

1. **Create `GenerationSettings` struct** in `mlx-testing/GenerationSettings.swift`
2. **Add `generationSettings` property** to `LLMService` protocol (or as a settable property)
3. **Update `LocalLLMServiceMLX`** to use `GenerationSettings` when building `GenerateParameters`
4. **Update `LocalLLMServiceStub`** to accept and ignore settings (or use maxTokens for stub length)
5. **Add `generationSettings`** to `ChatViewModel` with UserDefaults persistence
6. **Create `GenerationSettingsView`** as a private view in `ContentView.swift`
7. **Add toolbar button** with settings popover
8. **Verify:** Change temperature → observe different generation behavior

---

## Testing Strategy

- [ ] Default values: temperature 0.6, top-p 0.9, max tokens 2048
- [ ] Change temperature to 0.0 → responses are more deterministic/repetitive
- [ ] Change temperature to 1.5 → responses are more varied/creative
- [ ] Change max tokens to 128 → responses are cut short at ~128 tokens
- [ ] Settings persist across app restart
- [ ] "Reset to Defaults" restores original values
- [ ] Stub backend respects max tokens (or gracefully ignores)
- [ ] Settings popover opens/closes cleanly

---

## Open Questions

1. **Should parameters be displayed in the status bar?**
   - Recommendation: No, for now. The status bar already shows model name and generation status. Parameters are visible in the settings popover.

2. **Should we support per-model default parameters?**
   - Recommendation: Defer. Global defaults are sufficient for Milestone 2.4. Per-model defaults add complexity (model-specific preference storage).

3. **Should top-p be disabled when temperature is 0?**
   - Recommendation: No. Let users experiment freely. Temperature 0 with any top-p still works (greedy decoding ignores top-p).

---

*Related: [Requirements FR-1.5](../vision/02-requirements.md) · [Roadmap Milestone 2.4](../vision/06-roadmap.md)*
