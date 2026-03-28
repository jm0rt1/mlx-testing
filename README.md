    # mlx-testing — Local LLM Chat App for macOS

A native macOS SwiftUI chat application that runs large language models **locally on Apple Silicon** using [MLX Swift](https://github.com/ml-explore/mlx-swift) and [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm).

---

## Features

- **Real local LLM inference** — downloads and runs quantized models entirely on-device via MLX
- **Streaming token output** — replies appear word-by-word as the model generates
- **Stub mode** — develop and iterate on the UI without downloading a model
- **Runtime backend toggle** — switch between MLX and Stub from the toolbar
- **Cancel generation** — stop the model mid-reply with ⌘.
- **Download progress** — see model download percentage in the status bar
- **Chat bubble UI** — polished conversation layout with scroll-to-bottom
- **Model picker** — searchable toolbar popover to browse and select from 20+ models, with download status, disk/RAM sizes, and model notes
- **Dynamic model catalog** — fetches available MLX models from the Hugging Face API, with disk caching and periodic refresh
- **Context bubbles** — toggleable context snippets (skills, instructions, memories, custom) automatically composed into the system prompt
- **System prompt editor** — dedicated sheet for editing the base system prompt with a live composed-prompt preview
- **Agentic tool system** — LLM can invoke local tools (file system, shell, clipboard, app launcher, calendar) with user approval flow
- **Per-tool toggles** — enable or disable individual tools from a toolbar popover, with persistent preferences
- **Markdown rendering** — assistant replies render fenced code blocks, headings, lists, bold/italic, and inline code
- **Persistent settings** — context bubbles, system prompt, model catalog, and tool approvals are auto-saved to `~/Library/Application Support/mlx-testing/`

---

## Requirements

| Requirement | Minimum |
|---|---|
| Mac | Apple Silicon (M1 or later) |
| macOS | 14.0 Sonoma |
| Xcode | 16.0+ |
| RAM | 16 GB (24 GB+ recommended for 4B+ models) |

---

## Quick Start

### 1. Open the project

```bash
open mlx-testing.xcodeproj
```

### 2. Set your Team

In Xcode → **mlx-testing** target → **Signing & Capabilities** → set your **Team**.

### 3. Build & Run

Press **⌘R**. On first launch the app will fetch the model catalog from Hugging Face and download the default model (~5 GB for Qwen3-8B-4bit). Subsequent launches use the cached weights.

> **Tip:** Run outside the debugger (⌘⌥R → uncheck "Debug Executable") for noticeably faster inference.

---

## Package Dependencies

These are already added to the Xcode project:

| Package | URL | Version |
|---|---|---|
| **mlx-swift** | `https://github.com/ml-explore/mlx-swift.git` | 0.30.x |
| **mlx-swift-lm** | `https://github.com/ml-explore/mlx-swift-lm.git` | 2.30.x |

Linked products: `MLX`, `MLXFFT`, `MLXFast`, `MLXLinalg`, `MLXNN`, `MLXOptimizers`, `MLXRandom`, `MLXLLM`, `MLXLMCommon`, `MLXEmbedders`, `MLXVLM`.

---

## Entitlements

The entitlements file (`mlx_testing.entitlements`) configures:

| Entitlement | Why |
|---|---|
| `com.apple.security.app-sandbox` | Required for sandboxed macOS apps |
| `com.apple.security.network.client` | Model weights and catalog are downloaded from Hugging Face Hub |
| `com.apple.developer.kernel.increased-memory-limit` | LLMs need significant memory; this requests more from the OS |
| `com.apple.security.files.user-selected.read-write` | File system tool: read/write user-selected files |
| `com.apple.security.files.downloads.read-write` | File system tool: access the Downloads folder |
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | File system tool: read/write files relative to home directory |
| `com.apple.security.automation.apple-events` | App launcher tool: open applications via Apple Events |
| `com.apple.security.personal-information.calendars` | Calendar tool: read and write Apple Calendar events |

---

## Project Structure

```
mlx-testing/
├── mlx_testingApp.swift        # @main App entry point
├── ContentView.swift           # Main chat UI with sidebar, status bar, message bubbles, input bar, toolbar
├── ChatMessage.swift           # Message data model (id, role, text, date, tool call/result info)
├── ChatViewModel.swift         # ObservableObject driving the UI, chat state, and agentic tool loop
├── LocalLLMService.swift       # LLMService protocol + two implementations:
│   ├── LocalLLMServiceMLX        — real MLX inference
│   └── LocalLLMServiceStub       — simulated streaming (no model needed)
├── ModelInfo.swift             # Dynamic model entry (Codable) with HF metadata, download status, and RAM estimates
├── ModelCatalogService.swift   # Fetches MLX-compatible models from HF API, caches catalog to disk
├── ModelPickerView.swift       # Toolbar popover for selecting models with search, download status, and size info
├── ToolPickerView.swift        # Toolbar popover for browsing and toggling individual tools on/off
├── MarkdownView.swift          # Lightweight Markdown renderer (code blocks, headings, lists, inline formatting)
├── ContextBubble.swift         # Data model for toggleable context snippets (skill, instruction, memory, custom)
├── ContextBubbleEditor.swift   # Sidebar UI for managing context bubbles (add, edit, delete, toggle)
├── ContextStore.swift          # Persists context bubbles and base system prompt to disk with auto-save
├── SystemPromptEditor.swift    # Sheet UI for editing the base system prompt and previewing the composed prompt
├── AgentTools/                 # Agentic tool system
│   ├── AgentTool.swift           — Tool protocol, parameter/argument types, ToolCall, ToolResult, risk levels
│   ├── ToolRegistry.swift        — Central registry of available tools with schema generation
│   ├── ToolExecutor.swift        — Parses tool calls from LLM output and executes them
│   ├── FileSystemTool.swift      — Read, write, list, search files (medium risk)
│   ├── ShellCommandTool.swift    — Execute shell commands via /bin/bash (high risk)
│   ├── ClipboardTool.swift       — Read/write system clipboard (low risk)
│   ├── AppLauncherTool.swift     — Open apps, URLs, files, list running apps (medium risk)
│   └── CalendarTool.swift        — List, create, update, delete, and search Apple Calendar events (medium risk)
├── mlx_testing.entitlements    # Sandbox + network + memory + file access + automation entitlements
└── Assets.xcassets/
```

---

## Switching Between Stub and MLX

### At runtime (toolbar picker)

Use the **Backend** picker in the window toolbar to switch between:

- **MLX (real model)** — downloads & loads a real LLM, generates real replies
- **Stub (simulated)** — instant fake streaming, no network or model required

Switching resets the conversation.

### At build time

In `ChatViewModel.swift`, change the default in `init`:

```swift
init(backend: LLMBackend = .stub)   // stub by default
init(backend: LLMBackend = .mlx)    // MLX by default (current)
```

---

## Changing the Model

### At runtime (recommended)

Use the **Model Picker** in the toolbar to browse, search, and select from all available MLX-community models. The catalog is fetched from the Hugging Face API and cached locally. Models can be filtered by download status, RAM fit, and sorted by downloads, size, name, or family.

### At build time

In `ModelCatalogService.swift`, change the default model ID:

```swift
static let defaultModelID = "mlx-community/Qwen3-8B-4bit"
```

You can use **any** Hugging Face model with an MLX-compatible architecture — the `LocalLLMServiceMLX` creates a `ModelConfiguration` dynamically from the repo ID.

### Generation parameters

In `LocalLLMService.swift` → `LocalLLMServiceMLX`:

```swift
var generateParameters = GenerateParameters(maxTokens: 2048, temperature: 0.6)
```

- `temperature` — higher = more creative, lower = more deterministic
- `maxTokens` — maximum reply length in tokens

---

## How It Works

1. **App launches** → `ContentView` loads the model catalog and calls `vm.loadModelIfNeeded()`
2. **Catalog loading** → `ModelCatalogService` loads cached models from disk, then refreshes from the Hugging Face API if stale (>1 hour)
3. **Model loading** → `LocalLLMServiceMLX.load()` uses `LLMModelFactory.shared.loadContainer()` to download weights from Hugging Face Hub and load them via MLX
4. **System prompt composition** → `ContextStore` combines the base system prompt with all enabled context bubbles, and the tool registry appends available tool schemas
5. **Chat session** → A `ChatSession` is created with the loaded `ModelContainer`, composed system prompt, and generation parameters
6. **User sends message** → `ChatViewModel.send()` appends a user message, creates a placeholder assistant message, then enters the agentic loop
7. **Agentic loop** → `agenticLoop()` generates a reply, checks for `tool_call` JSON blocks, requests user approval, executes the tool, feeds the result back, and repeats (up to 10 iterations)
8. **Streaming** → `ChatSession.streamResponse(to:)` returns an `AsyncThrowingStream<String, Error>` — each chunk is appended to the assistant message in real time
9. **Response sanitization** → `<think>` and `<reasoning>` tags from chain-of-thought models are stripped from the output
10. **Cancellation** → Cancelling the `Task` terminates the stream; MLX cleans up
11. **Model selection** → `ModelPickerView` lets the user choose a different model from the dynamic catalog; selecting a new model triggers a reload

MLX uses Apple Silicon's **unified memory** and **Metal GPU acceleration** automatically — no Metal shader code needed.

---

## Agentic Tool System

The app includes an agentic tool system that lets the LLM invoke local tools during conversation. When tools are enabled, the model can request actions by emitting a `tool_call` JSON block in its response.

### Built-in Tools

| Tool | Name | Risk | Description |
|---|---|---|---|
| File System | `file_system` | Medium | Read, write, list, and search files |
| Shell | `shell` | High | Execute shell commands via `/bin/bash` (30s timeout) |
| Clipboard | `clipboard` | Low | Read/write the system clipboard |
| App Launcher | `open` | Medium | Open apps, URLs, files, or list running applications |
| Calendar | `calendar` | Medium | List calendars, query/create/update/delete/search Apple Calendar events |

### Approval Flow

- **Low risk** tools still require one-time approval
- **Medium/high risk** tools show a detailed approval sheet with argument preview
- Users can choose **Allow**, **Always Allow** (persisted), or **Deny**
- The agentic loop runs up to 10 iterations per user message

### Adding a New Tool

1. Create a new Swift file in `AgentTools/` conforming to the `AgentTool` protocol
2. Define `name`, `toolDescription`, `parameters`, `requiresApproval`, and `riskLevel`
3. Implement `execute(arguments:)` returning a `ToolResult`
4. Register it in `ToolRegistry.registerDefaults()`:

```swift
func registerDefaults() {
    register(FileSystemTool())
    register(ShellCommandTool())
    register(ClipboardTool())
    register(AppLauncherTool())
    register(MyNewTool())      // ← add here
}
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| "Failed to load" on launch | Check internet connection; model download requires network |
| Slow first token | Normal — the model must be loaded into GPU memory on first use |
| App uses too much memory | Try a smaller model (1B–3B) or reduce `maxTokens` |
| Build error about missing modules | Ensure both SPM packages resolved (File → Packages → Resolve Package Versions) |
| Sandbox error on download | Confirm `com.apple.security.network.client` is `true` in entitlements |

---

## Vision & Roadmap

For the full product vision, architecture, and phased roadmap, see the **[Vision Documents](docs/vision/)**:

| Document | Summary |
|---|---|
| [Concept](docs/vision/01-concept.md) | High-level vision, guiding principles, value proposition |
| [Requirements](docs/vision/02-requirements.md) | Functional & non-functional requirements |
| [Domain Model](docs/vision/03-domain-model.md) | Core entities and data flows |
| [Features & Use Cases](docs/vision/04-features-and-use-cases.md) | Feature catalog and user stories |
| [Architecture](docs/vision/05-architecture.md) | Target architecture and integration patterns |
| [Roadmap](docs/vision/06-roadmap.md) | Phased delivery plan with milestones |

### Next Steps
## Agent Instructions

The repository includes Copilot/agent instructions to help AI coding assistants work effectively:

| File | Purpose |
|---|---|
| `.github/copilot-instructions.md` | Global instructions: architecture overview, Swift conventions, patterns, entitlements, tool system, and PR checklist |
| `.github/pull_request_template.md` | PR template with checklist covering code quality and documentation updates |

These files are automatically picked up by GitHub Copilot and other AI agents when working in this repository.

---

## Next Steps

- [x] Add model picker UI (choose from model catalog at runtime)
- [x] Context bubbles — inject skills, instructions, and memories into the system prompt
- [x] System prompt editor with composed-prompt preview
- [x] Persist context bubbles and system prompt to disk
- [x] Agentic tool calling with approval flow
- [x] Dynamic model catalog fetched from Hugging Face API
- [x] Markdown rendering for assistant replies (code blocks, headings, lists)
- [x] Agentic tool system with file, shell, clipboard, and app launcher tools
- [x] Tool approval UI with risk levels and always-approve option
- [ ] Add token-per-second metrics display
- [ ] Persist conversation history to disk
- [ ] Add VLM (vision) support via `MLXVLM`
- [ ] Add embeddings / RAG pipeline via `MLXEmbedders`
- [ ] Menu bar agent and global keyboard shortcut

---

## Credits

- [MLX](https://github.com/ml-explore/mlx) — Apple's array framework for machine learning on Apple Silicon
- [MLX Swift](https://github.com/ml-explore/mlx-swift) — Swift API for MLX
- [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) — LLM/VLM support for MLX Swift
- [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples) — Official example applications

## License

MIT
