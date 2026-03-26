# Copilot Instructions — mlx-testing

## Project Overview

**mlx-testing** is a native macOS SwiftUI chat application that runs large language models locally on Apple Silicon using MLX Swift and MLX Swift LM. All source files live in the `mlx-testing/` directory.

- **Language:** Swift 5.9+
- **UI framework:** SwiftUI (macOS 14.0+)
- **ML frameworks:** MLX Swift (`MLX`, `MLXFFT`, `MLXFast`, `MLXLinalg`, `MLXNN`, `MLXOptimizers`, `MLXRandom`), MLX Swift LM (`MLXLLM`, `MLXLMCommon`, `MLXEmbedders`, `MLXVLM`)
- **Package manager:** Swift Package Manager (via Xcode)
- **Target platform:** macOS on Apple Silicon (M1+)

## Build & Run

The project is built with Xcode 16.0+. There is no command-line `swift build` or `swift test` — it relies on Xcode schemes and the macOS sandbox.

```
open mlx-testing.xcodeproj    # Open in Xcode
# Build: ⌘B
# Run:   ⌘R
```

There are currently no unit tests or CI workflows in the repository.

## Architecture

| Layer | Files | Purpose |
|---|---|---|
| App entry | `mlx_testingApp.swift` | `@main` SwiftUI App |
| Views | `ContentView.swift`, `ModelPickerView.swift`, `ContextBubbleEditor.swift`, `SystemPromptEditor.swift`, `MarkdownView.swift` | All UI is SwiftUI; no UIKit or AppKit views |
| View model | `ChatViewModel.swift` | Single `@MainActor ObservableObject` driving all UI state |
| Services | `LocalLLMService.swift`, `ModelCatalogService.swift` | Protocol-based LLM abstraction + HF API catalog |
| Data models | `ChatMessage.swift`, `ContextBubble.swift`, `ModelInfo.swift` | Plain structs, `Identifiable`, `Codable`, `Hashable` |
| Persistence | `ContextStore.swift` | Saves to `~/Library/Application Support/mlx-testing/` via JSON + text files |
| Agent tools | `AgentTools/AgentTool.swift`, `ToolRegistry.swift`, `ToolExecutor.swift`, `FileSystemTool.swift`, `ShellCommandTool.swift`, `ClipboardTool.swift`, `AppLauncherTool.swift` | Extensible tool system the LLM can invoke |
| Config | `mlx_testing.entitlements` | macOS sandbox + network + memory + file access entitlements |

## Swift Conventions

1. **`@MainActor` for all observable classes.** `ChatViewModel`, `ContextStore`, `ModelCatalogService`, `ToolRegistry`, and `ToolExecutor` are all `@MainActor`. New ObservableObjects must also be `@MainActor`.
2. **Protocol-oriented design.** The LLM backend is abstracted via the `LLMService` protocol with two conformances (`LocalLLMServiceMLX`, `LocalLLMServiceStub`). New backends should conform to this protocol.
3. **`AgentTool` protocol for tools.** Every tool conforms to `AgentTool` and is registered in `ToolRegistry.registerDefaults()`. New tools follow the same pattern.
4. **Value types for data models.** `ChatMessage`, `ContextBubble`, `ModelInfo`, `ToolParameter`, `ToolCall`, `ToolResult`, `ToolArtifact` are all structs.
5. **Modern Swift concurrency.** Use `async/await` and `Task` — no Dispatch queues or completion handlers.
6. **Combine only for auto-save debouncing.** `ContextStore` uses `Publishers.Merge` + `.debounce` for auto-save. Elsewhere, prefer async/await.
7. **No force-unwraps in new code** except for well-known safe cases (`FileManager.default.urls` which always returns at least one entry).
8. **Comments style.** Concise single-line `//` comments or `///` doc comments. Use `// MARK: -` section headers to organize files. No verbose block comments.
9. **Naming.** Follow Swift API Design Guidelines — clear, unambiguous names. Use camelCase for properties/methods, PascalCase for types.

## Entitlements

The app sandbox is enabled. Current entitlements:

| Key | Purpose |
|---|---|
| `com.apple.security.app-sandbox` | macOS sandbox requirement |
| `com.apple.security.network.client` | Download model weights from Hugging Face |
| `com.apple.developer.kernel.increased-memory-limit` | LLMs need significant memory |
| `com.apple.security.files.user-selected.read-write` | User-chosen files for tool system |
| `com.apple.security.files.downloads.read-write` | Access Downloads folder |
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Home directory access for file tools |
| `com.apple.security.automation.apple-events` | App launcher tool |

If a new tool needs additional sandbox access, update **both** the entitlements plist and this table.

---

## SwiftUI Views

### Structure

- All views are SwiftUI structs. No UIKit or AppKit view controllers.
- `ContentView` is the root — it creates the `ChatViewModel` as a `@StateObject` and passes state down.
- Private sub-views (e.g. `ChatBubble`, `InputBar`, `StatusBar`, `ModelRow`) are declared with `private` access inside the same file as their parent.
- Use `@ObservedObject` when a view receives an existing observable. Use `@StateObject` only at the creation site (`ContentView` for `ChatViewModel`).
- Use `NavigationSplitView` for the sidebar/detail layout. Do not switch to `NavigationStack`.

### Data flow

```
ContentView (@StateObject ChatViewModel)
├── ContextBubbleEditor (@ObservedObject ContextStore)
├── StatusBar (plain values from VM)
├── ChatBubble → MarkdownView (message text)
├── InputBar (@Binding input, closures)
├── ModelPickerView (@Binding selectedModelID, @ObservedObject ModelCatalogService)
└── SystemPromptEditor (@ObservedObject ContextStore)
```

### When adding new views

1. Place the file in `mlx-testing/` (flat structure, no subdirectories for views).
2. If the view is only used inside one parent, make it `private struct` in the same file.
3. If the view needs the full VM, pass the whole `ChatViewModel` as `@ObservedObject`. If it only needs a subset, prefer passing specific bindings or plain values.
4. Prefer extracted `@ViewBuilder` computed properties or private sub-views over deeply nested closures.
5. Update the README project structure table.

---

## Model & Service Layer

### LLMService protocol

```swift
protocol LLMService: AnyObject {
    var isLoaded: Bool { get }
    var downloadProgress: Double { get }
    var statusMessage: String { get }
    func load() async throws
    func generateReplyStreaming(
        from messages: [ChatMessage],
        systemPrompt: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws
    func cancelGeneration()
}
```

Two implementations: `LocalLLMServiceMLX` (real MLX inference) and `LocalLLMServiceStub` (fake streaming for UI development). New backends must conform to `LLMService`.

### ChatViewModel

- Drives all published UI state: messages, loading, status, download progress.
- Owns the agentic loop (`agenticLoop()`): generate → parse tool call → approve → execute → feed back.
- `sanitizeResponse(_:)` strips `<think>` / `<reasoning>` tags. Add new patterns there for other model families.
- The composed system prompt is: `ContextStore.composedSystemPrompt` + tool schemas (when tools enabled).

### Data models

- **`ChatMessage`** roles: `.user`, `.assistant`, `.system`, `.toolCall`, `.toolResult`. Tool messages carry `ToolCallInfo` / `ToolResultInfo`.
- **`ContextBubble`** types: `.skill`, `.instruction`, `.memory`, `.custom`. All `Codable`, persisted as JSON.
- **`ModelInfo`** is populated from the HF API (not hardcoded). Derived properties compute display name, family, quant label, RAM estimate.

### Persistence

| Store | Location | Format |
|---|---|---|
| Context bubbles | `~/Library/Application Support/mlx-testing/contexts.json` | JSON array of `ContextBubble` |
| System prompt | `~/Library/Application Support/mlx-testing/system_prompt.txt` | Plain text |
| Model catalog | `~/Library/Application Support/mlx-testing/model_catalog.json` | JSON array of `ModelInfo` |
| Catalog metadata | `~/Library/Application Support/mlx-testing/catalog_metadata.json` | JSON with last-refresh date |
| Model weights | `~/Library/Caches/models/` | MLX-managed safetensors + config |
| Selected model | `UserDefaults` key `"selectedModelID"` | String |
| Tool approvals | `UserDefaults` key `"tool_always_approved"` | String array |

---

## Agent Tool System

### Architecture

```
AgentTool (protocol)
├── FileSystemTool      — read/write/list/info/search files
├── ShellCommandTool    — execute /bin/bash commands with timeout
├── ClipboardTool       — read/write NSPasteboard
└── AppLauncherTool     — open apps/URLs/files, list running apps

ToolRegistry (singleton) — registers tools, generates schema prompt, manages approvals
ToolExecutor            — parses tool_call JSON from LLM output, validates params, executes
```

### Adding a new tool

1. Create `mlx-testing/AgentTools/YourNewTool.swift`.
2. Define a struct conforming to `AgentTool`:
   - Set `name` (unique identifier used in JSON), `toolDescription`, `parameters`, `requiresApproval`, `riskLevel`.
   - Implement `execute(arguments:)` returning a `ToolResult`.
3. Register in `ToolRegistry.registerDefaults()`: `register(YourNewTool())`
4. If the tool needs new sandbox permissions, update `mlx_testing.entitlements`.
5. Update the README project structure table.

### Conventions

- **Risk levels:** `low` = read-only/benign, `medium` = writes files/launches apps, `high` = runs arbitrary commands.
- **Truncate large outputs.** Use a `maxChars` constant (5,000–10,000) and append a truncation notice.
- **Return `ToolResult` with `success: false`** for expected failures (file not found, etc.). Throw `ToolError` only for truly unexpected failures.
- **Path safety.** Resolve relative paths to the home directory via `NSHomeDirectory()`.
- **Parameter schemas.** Include `enumValues` for fixed-choice parameters. Always mark required params with `required: true`.

### Tool call JSON format

The LLM wraps calls in a fenced ` ```tool_call ` block:
```json
{"tool": "tool_name", "arguments": {"param1": "value1"}}
```

`ToolExecutor.parseToolCall(from:)` recognizes three fencing variants: `tool_call`, `json` (with a `"tool"` key), and plain fenced blocks (with a `"tool"` key).

---

## Key Patterns to Preserve

- **Streaming replies.** Generation always streams tokens via `onToken` callback. Never buffer entire responses.
- **Cancellation.** All generation tasks must honor `Task.checkCancellation()` and `generationTask?.cancel()`.
- **Agentic loop.** `ChatViewModel.agenticLoop()` is the orchestrator: generate → parse tool call → approve → execute → feed result → loop. Maximum 10 iterations.
- **Tool approval flow.** High/medium-risk tools require user approval via `requestApproval(for:)` / `respondToApproval(_:)` using `CheckedContinuation`.
- **Response sanitization.** `<think>` and `<reasoning>` tags are stripped by `sanitizeResponse(_:)`. New models may introduce other tags — handle them there.
- **Model catalog is dynamic.** `ModelCatalogService` fetches from the HF API and persists to disk. There is no hardcoded model array.

---

## Documentation

### Documentation Structure

The project has a comprehensive documentation structure under `docs/`:

```
docs/
├── README.md                    # Documentation index (start here)
├── vision/                      # Product vision and strategy
│   ├── 01-concept.md            #   What and why
│   ├── 02-requirements.md       #   FR/NFR with MoSCoW priority
│   ├── 03-domain-model.md       #   Entities, relationships, data flows
│   ├── 04-features-and-use-cases.md  #   Feature catalog and user stories
│   ├── 05-architecture.md       #   Target architecture and module boundaries
│   └── 06-roadmap.md            #   Phased delivery plan
├── design/                      # Technical design documents (TDDs)
│   ├── phase2-conversation-persistence.md
│   ├── phase2-generation-metrics.md
│   └── phase2-generation-parameters.md
├── guides/                      # Developer and contributor guides
│   ├── development-setup.md     #   Environment setup, build, run
│   ├── adding-tools.md          #   Step-by-step tool creation
│   └── contributing.md          #   Contribution workflow and conventions
└── decisions/                   # Architectural Decision Records (ADRs)
    ├── 001-mlx-swift-for-inference.md
    ├── 002-file-based-persistence.md
    └── 003-protocol-oriented-services.md
```

### When to update documentation

- **New Swift file added** → update the README project structure tree
- **New feature** → add to the README features list and describe in the relevant section
- **New dependency** → add to the README Package Dependencies table
- **New entitlement** → add to the README Entitlements table and the entitlements section in this file
- **New tool added** → mention in README Features list and Project Structure
- **New milestone planned** → create a technical design document in `docs/design/`
- **Significant design decision** → create an ADR in `docs/decisions/`
- **Architecture change** → update `docs/vision/05-architecture.md` and this file
- **New development workflow** → update or add a guide in `docs/guides/`

### Formatting conventions

- Tables use `|---|---|` alignment rows
- Code blocks use triple backticks with language tags (`swift`, `bash`, `json`)
- The project structure uses a tree-style `├──` / `└──` diagram
- Keyboard shortcuts: `⌘`, `⌥`, `⇧` (symbols, not spelled out)
- Bullet lists use `-` (not `*`)
- Section separators use `---`
- Each document includes navigation links to previous/next documents where applicable

### Design documents

Before implementing a new milestone, check `docs/design/` for a technical design document (TDD). TDDs specify:
- Data model changes (new structs, modified properties)
- API surface changes (new methods on existing types)
- Storage approach (file paths, UserDefaults keys)
- UI changes (new views, modified existing views)
- Implementation plan (ordered steps)

If no TDD exists for a milestone, create one using the template in `docs/design/README.md`.

### Architectural Decision Records

When making significant design choices (new dependency, new pattern, architectural change), document the decision in `docs/decisions/` using the ADR template. Include context, decision, rationale, alternatives considered, and consequences.

---

## Current Project State & Future Task Context

### Phase 1 (Foundation) — Complete ✅

The core chat application is fully functional:
- Local LLM inference via MLX with streaming and cancellation
- Dynamic model catalog from HuggingFace API with runtime model switching
- Context bubbles and system prompt composition
- Agentic tool system with approval flow (file system, shell, clipboard, app launcher)
- Persistent settings (context, system prompt, model selection, tool approvals)

### Phase 2 (Continuity) — Next Priority

The immediate development priorities are documented in `docs/design/`:

1. **Conversation Persistence** (Milestone 2.1) — See `docs/design/phase2-conversation-persistence.md`
   - New `Conversation` struct and `ConversationManager` class
   - JSON storage in `~/Library/Application Support/mlx-testing/conversations/`
   - Auto-save with Combine debounce (same pattern as `ContextStore`)
   - Integration with `ChatViewModel` via bridged `messages` property

2. **Performance Metrics** (Milestone 2.3) — See `docs/design/phase2-generation-metrics.md`
   - New `GenerationMetrics` struct on `ChatMessage`
   - Live tokens-per-second counter in status bar
   - Post-generation metrics footer on assistant messages

3. **Generation Parameters** (Milestone 2.4) — See `docs/design/phase2-generation-parameters.md`
   - New `GenerationSettings` struct with temperature, top-p, max tokens
   - Settings popover in toolbar
   - UserDefaults persistence

### Phase 3 (Multimodal) and Phase 4 (OS Companion)

Longer-term milestones are described in `docs/vision/06-roadmap.md`:
- VLM support via MLXVLM (Milestone 3.1)
- RAG pipeline with local embeddings via MLXEmbedders (Milestones 3.3–3.4)
- Menu bar agent (Milestone 4.1)
- macOS Services and Shortcuts integration (Milestones 4.3–4.4)

### Key Architectural Decisions

These decisions inform all future development (details in `docs/decisions/`):
- **ADR-001:** MLX Swift is the sole inference backend — no llama.cpp, Core ML, or ONNX
- **ADR-002:** File-based persistence (JSON) over Core Data/SQLite — simple, human-readable, no migrations
- **ADR-003:** Protocol-oriented services — all subsystems accessed via protocols for testability and extensibility

---

## PR Checklist

When submitting changes, verify:

- [ ] New Swift files are placed in `mlx-testing/` (or `mlx-testing/AgentTools/` for tools).
- [ ] `@MainActor` is used on any new `ObservableObject` class.
- [ ] New tools are registered in `ToolRegistry.registerDefaults()`.
- [ ] Entitlements plist is updated if new sandbox permissions are needed.
- [ ] README project structure table is updated for new files.
- [ ] No hardcoded model IDs outside `ModelCatalogService.defaultModelID`.
- [ ] All async work supports cancellation via `Task.checkCancellation()`.
- [ ] Large tool outputs are truncated with a character limit.
- [ ] Technical design document consulted (if implementing a documented milestone).
- [ ] Documentation updated for any architectural or structural changes.
