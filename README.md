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
- **Context bubbles** — toggleable context snippets (skills, instructions, memories, custom) automatically composed into the system prompt
- **System prompt editor** — dedicated sheet for editing the base system prompt with a live composed-prompt preview
- **Persistent settings** — context bubbles and base system prompt are auto-saved to `~/Library/Application Support/mlx-testing/`

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

Press **⌘R**. On first launch the app will download the default model (~2–3 GB for Qwen3-4B-4bit) from Hugging Face. Subsequent launches use the cached weights.

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
| `com.apple.security.network.client` | Model weights are downloaded from Hugging Face Hub |
| `com.apple.developer.kernel.increased-memory-limit` | LLMs need significant memory; this requests more from the OS |

---

## Project Structure

```
mlx-testing/
├── mlx_testingApp.swift        # @main App entry point
├── ContentView.swift           # Main chat UI with sidebar, status bar, message bubbles, input bar, toolbar
├── ChatMessage.swift           # Message data model (id, role, text, date)
├── ChatViewModel.swift         # ObservableObject driving the UI and managing chat state
├── LocalLLMService.swift       # LLMService protocol + two implementations:
│   ├── LocalLLMServiceMLX        — real MLX inference
│   └── LocalLLMServiceStub       — simulated streaming (no model needed)
├── ModelInfo.swift             # Catalog of 20+ available LLMs with download status and memory requirements
├── ModelPickerView.swift       # Toolbar popover for selecting models with search, download status, and size info
├── ContextBubble.swift         # Data model for toggleable context snippets (skill, instruction, memory, custom)
├── ContextBubbleEditor.swift   # Sidebar UI for managing context bubbles (add, edit, delete, toggle)
├── ContextStore.swift          # Persists context bubbles and base system prompt to disk with auto-save
├── SystemPromptEditor.swift    # Sheet UI for editing the base system prompt and previewing the composed prompt
├── mlx_testing.entitlements    # Sandbox + network + memory entitlements
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

In `LocalLLMService.swift` → `LocalLLMServiceMLX`, change:

```swift
var modelConfiguration: ModelConfiguration = LLMRegistry.qwen3_4b_4bit
```

### Recommended models for 24 GB RAM

| Model | Registry constant | ~Memory | Notes |
|---|---|---|---|
| Gemma 3 1B QAT 4-bit | `LLMRegistry.gemma3_1B_qat_4bit` | ~0.7 GB | Ultra-fast, great for testing |
| Qwen3 4B 4-bit | `LLMRegistry.qwen3_4b_4bit` | ~2.5 GB | Fast, good quality |
| Llama 3.2 3B 4-bit | `LLMRegistry.llama3_2_3B_4bit` | ~2 GB | Compact |
| SmolLM3 3B 4-bit | `LLMRegistry.smollm3_3b_4bit` | ~2 GB | Compact |
| **Qwen3 8B 4-bit** (default) | `LLMRegistry.qwen3_8b_4bit` | ~5 GB | Best quality/speed balance for 24 GB |
| Llama 3.1 8B 4-bit | `LLMRegistry.llama3_1_8B_4bit` | ~5 GB | Strong all-around |
| Gemma 2 9B 4-bit | `LLMRegistry.gemma_2_9b_it_4bit` | ~6 GB | Great quality |
| GLM-4 9B 4-bit | `LLMRegistry.glm4_9b_4bit` | ~6 GB | Tool calling support |
| DeepSeek R1 7B 4-bit | `LLMRegistry.deepSeekR1_7B_4bit` | ~5 GB | Reasoning model |
| Qwen3 MoE 30B-A3B 4-bit | `LLMRegistry.qwen3MoE_30b_a3b_4bit` | ~17 GB | 30B total, only 3B active — tight fit, best quality |

You can also load **any** Hugging Face model with an MLX-compatible architecture:

```swift
var modelConfiguration = ModelConfiguration(id: "mlx-community/YOUR-MODEL-ID")
```

### Generation parameters

```swift
var generateParameters = GenerateParameters(maxTokens: 2048, temperature: 0.6)
```

- `temperature` — higher = more creative, lower = more deterministic
- `maxTokens` — maximum reply length in tokens

---

## How It Works

1. **App launches** → `ContentView` calls `vm.loadModelIfNeeded()`
2. **Model loading** → `LocalLLMServiceMLX.load()` uses `LLMModelFactory.shared.loadContainer()` to download weights from Hugging Face Hub and load them via MLX
3. **System prompt composition** → `ContextStore` combines the base system prompt with all enabled context bubbles into a single composed prompt
4. **Chat session** → A `ChatSession` is created with the loaded `ModelContainer`, composed system prompt, and generation parameters
5. **User sends message** → `ChatViewModel.send()` appends a user message, creates a placeholder assistant message, then calls `generateReplyStreaming()`
6. **Streaming** → `ChatSession.streamResponse(to:)` returns an `AsyncThrowingStream<String, Error>` — each chunk is appended to the assistant message in real time
7. **Cancellation** → Cancelling the `Task` terminates the stream; MLX cleans up
8. **Model selection** → `ModelPickerView` lets the user choose a different model from the catalog; selecting a new model triggers a reload

MLX uses Apple Silicon's **unified memory** and **Metal GPU acceleration** automatically — no Metal shader code needed.

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

For the full product vision, architecture, and phased roadmap, see the **[Vision Documents](VISION.md)**:

| Document | Summary |
|---|---|
| [Concept](VISION-01-concept.md) | High-level vision, guiding principles, value proposition |
| [Requirements](VISION-02-requirements.md) | Functional & non-functional requirements |
| [Domain Model](VISION-03-domain-model.md) | Core entities and data flows |
| [Features & Use Cases](VISION-04-features-and-use-cases.md) | Feature catalog and user stories |
| [Architecture](VISION-05-architecture.md) | Target architecture and integration patterns |
| [Roadmap](VISION-06-roadmap.md) | Phased delivery plan with milestones |

### Next Steps

- [x] Add model picker UI (choose from model catalog at runtime)
- [x] Context bubbles — inject skills, instructions, and memories into the system prompt
- [x] System prompt editor with composed-prompt preview
- [x] Persist context bubbles and system prompt to disk
- [x] Agentic tool calling with approval flow
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
