# Generation Metrics — Milestone 2.3

> Technical design for capturing and displaying tokens-per-second performance metrics.

**Status:** Ready for implementation
**Milestone:** [2.3 — Performance Metrics](../vision/06-roadmap.md)
**Requirements:** [FR-1.4](../vision/02-requirements.md), [NFR-1.1](../vision/02-requirements.md), [NFR-1.2](../vision/02-requirements.md)

---

## Overview

Users currently have no visibility into model performance. This design adds live tokens-per-second tracking during generation, and post-generation summary metrics attached to each assistant message. This helps users evaluate models, choose the right model for their hardware, and understand generation behavior.

## Goals

- Display a live tokens-per-second counter during generation
- Attach final metrics (token count, speed, duration) to completed assistant messages
- Capture time-to-first-token latency
- Keep the metrics display unobtrusive (small text, muted color)

## Non-Goals

- Historical performance analytics or charts
- Cross-model performance comparison UI
- Prompt token counting (requires tokenizer access — deferred)

---

## Current State

### What Exists

- `LocalLLMServiceMLX.generateReplyStreaming()` streams tokens via an `onToken` callback
- `ChatViewModel` counts received tokens implicitly by appending to message text
- The status bar shows "Generating…" during inference but no speed data
- `ChatMessage` has no metrics fields

### What's Missing

- No timing instrumentation around token generation
- No `GenerationMetrics` data model
- No UI for metrics display

---

## Proposed Design

### Data Model

#### `GenerationMetrics` (new struct)

```swift
struct GenerationMetrics: Codable, Hashable {
    var completionTokens: Int
    var tokensPerSecond: Double
    var timeToFirstToken: TimeInterval
    var totalDuration: TimeInterval
    
    var formattedSummary: String {
        let tps = String(format: "%.1f", tokensPerSecond)
        let duration = String(format: "%.1f", totalDuration)
        return "\(completionTokens) tokens · \(tps) tok/s · \(duration)s"
    }
}
```

Place in: `mlx-testing/ChatMessage.swift` (alongside `ChatMessage`)

#### `ChatMessage` Extension

```swift
struct ChatMessage: Identifiable, Codable, Hashable {
    // ... existing fields ...
    var metrics: GenerationMetrics?  // New: populated for assistant messages
}
```

**Design decision:** `metrics` is optional and only populated for completed assistant messages. It is `Codable` so it persists with conversation history (Milestone 2.1).

### Metrics Collection

Metrics are collected in `ChatViewModel` around the existing streaming loop:

```swift
// In ChatViewModel, inside the generation flow:

let generationStart = CFAbsoluteTimeGetCurrent()
var firstTokenTime: CFAbsoluteTime?
var tokenCount = 0

try await llmService.generateReplyStreaming(
    from: messages,
    systemPrompt: systemPrompt
) { token in
    if firstTokenTime == nil {
        firstTokenTime = CFAbsoluteTimeGetCurrent()
    }
    tokenCount += 1
    self.messages[idx].text += token
    
    // Update live metrics
    let elapsed = CFAbsoluteTimeGetCurrent() - generationStart
    if elapsed > 0 {
        self.liveTokensPerSecond = Double(tokenCount) / elapsed
    }
}

// After generation completes:
let totalDuration = CFAbsoluteTimeGetCurrent() - generationStart
let ttft = (firstTokenTime ?? generationStart) - generationStart

messages[idx].metrics = GenerationMetrics(
    completionTokens: tokenCount,
    tokensPerSecond: totalDuration > 0 ? Double(tokenCount) / totalDuration : 0,
    timeToFirstToken: ttft,
    totalDuration: totalDuration
)
```

### ChatViewModel Changes

```swift
class ChatViewModel: ObservableObject {
    // ... existing properties ...
    
    // New: live metrics during generation
    @Published var liveTokensPerSecond: Double = 0
    @Published var liveTokenCount: Int = 0
    
    // Reset at generation start
    private func resetLiveMetrics() {
        liveTokensPerSecond = 0
        liveTokenCount = 0
    }
}
```

### UI Changes

#### Status Bar (during generation)

Update the existing `StatusBar` in `ContentView.swift` to show live metrics:

```swift
// Current: "Generating…"
// New:     "Generating… 42 tok/s"

if vm.isGenerating {
    Text("Generating… \(String(format: "%.0f", vm.liveTokensPerSecond)) tok/s")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

#### Message Bubble Footer (after generation)

Add a subtle metrics line below completed assistant messages:

```swift
// Inside ChatBubble, for assistant messages with metrics:
if let metrics = message.metrics {
    Text(metrics.formattedSummary)
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, 2)
}
```

**Style:** `.caption2` font, `.tertiary` foreground — visible but unobtrusive. Matches the existing muted timestamp style.

---

## Implementation Plan

1. **Add `GenerationMetrics` struct** to `ChatMessage.swift`
2. **Add `metrics` property** to `ChatMessage`
3. **Add live metrics properties** to `ChatViewModel` (`liveTokensPerSecond`, `liveTokenCount`)
4. **Instrument the generation loop** in `ChatViewModel` with timing and counting
5. **Update `StatusBar`** to show live tok/s during generation
6. **Update `ChatBubble`** to show metrics footer on completed assistant messages
7. **Verify:** Metrics display correctly for MLX backend and show 0 gracefully for stub

---

## Testing Strategy

- [ ] Send a message with MLX backend → live tok/s counter appears and updates
- [ ] After generation completes → metrics footer shows on the assistant message
- [ ] Cancel generation mid-reply → partial metrics are recorded and displayed
- [ ] Stub backend → metrics show correctly (simulated speed)
- [ ] Conversation persistence (if implemented) → metrics survive app restart
- [ ] Metrics formatting: no NaN, no negative values, no division by zero

---

## Open Questions

1. **Should prompt token count be included?**
   - Recommendation: Defer. Counting prompt tokens requires running the tokenizer, which adds complexity. Focus on completion metrics first.

2. **Should metrics be visible by default or toggled?**
   - Recommendation: Visible by default. They're small and informative. Add a setting to hide them later if users request it.

3. **How to handle metrics during the agentic loop?**
   - Recommendation: Each generation pass within the loop gets its own metrics. The final assistant message shows cumulative metrics (sum of tokens, average tok/s, total duration).

---

*Related: [Requirements FR-1.4](../vision/02-requirements.md) · [Roadmap Milestone 2.3](../vision/06-roadmap.md)*
