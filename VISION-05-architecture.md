# 5 — Architecture

This document describes the target architecture for MLX Copilot, including module boundaries, dependency flow, integration patterns, and how the current codebase evolves to support the full vision.

---

## Architecture Principles

1. **Protocol-driven boundaries** — Every major subsystem is accessed through a Swift protocol, enabling testability and backend swapping (MLX vs. Stub vs. Cloud).
2. **Unidirectional data flow** — UI observes `@Published` state on `ObservableObject` view models; mutations flow through defined methods.
3. **Actor isolation** — Inference and indexing work runs on dedicated actors to avoid blocking the main thread.
4. **File-based persistence** — Simple, inspectable JSON and binary files in `~/Library/Application Support/`. No SQLite or Core Data unless justified by scale.
5. **Minimal external dependencies** — Only MLX Swift ecosystem packages. No Alamofire, no Realm, no Firebase.

---

## Module Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Presentation                               │
│                                                                         │
│  ContentView   ModelPickerView   ContextBubbleEditor   SystemPromptEditor│
│  ChatBubble    InputBar          StatusBar             MenuBarPanel      │
│                                                                         │
│  (SwiftUI Views — observe ViewModels, dispatch user actions)            │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ @StateObject / @ObservedObject
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              View Models                                │
│                                                                         │
│  ChatViewModel         ContextStore         ModelCatalogService          │
│  ConversationManager   WorkspaceManager     SettingsStore                │
│                                                                         │
│  (ObservableObjects — coordinate services, hold UI state)               │
└──────┬────────────────────┬────────────────────┬────────────────────────┘
       │                    │                    │
       ▼                    ▼                    ▼
┌──────────────┐  ┌──────────────────┐  ┌───────────────────────┐
│  Inference   │  │  Knowledge       │  │  Agent                │
│  Engine      │  │  Layer           │  │  System               │
│              │  │                  │  │                       │
│  LLMService  │  │  EmbeddingService│  │  ToolRegistry         │
│  VLMService  │  │  VectorIndex     │  │  ToolExecutor         │
│  Embedding   │  │  DocumentLoader  │  │  AgentTool (protocol) │
│  Service     │  │  ChunkSplitter   │  │  ApprovalManager      │
│              │  │  SearchEngine    │  │  WorkflowEngine       │
└──────┬───────┘  └──────┬───────────┘  └───────┬───────────────┘
       │                 │                      │
       ▼                 ▼                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           Platform Layer                                │
│                                                                         │
│  MLX / MLXLLM / MLXVLM / MLXEmbedders    (Apple MLX frameworks)        │
│  FileManager / FSEvents                    (File system)                │
│  NSPasteboard / NSWorkspace                (macOS APIs)                  │
│  Process / NSTask                          (Shell execution)            │
│  URLSession                                (HF API / model download)    │
│  UserDefaults / JSON files                 (Persistence)                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Module Descriptions

### Presentation Layer

Pure SwiftUI views with no business logic. Views bind to view model `@Published` properties and call view model methods for user actions.

| Component | Responsibility |
|---|---|
| `ContentView` | Main window layout: sidebar + chat detail |
| `ChatBubble` | Renders a single message (text, tool call, tool result, images, citations) |
| `InputBar` | Text input with send/cancel, image attachment, screenshot capture |
| `StatusBar` | Model name, generation status, download progress, metrics |
| `ModelPickerView` | Searchable model catalog popover |
| `ContextBubbleEditor` | Sidebar for context bubble CRUD |
| `SystemPromptEditor` | Sheet for base prompt editing and composed prompt preview |
| `MenuBarPanel` | *(Future)* Compact floating panel for menu bar agent |
| `ConversationList` | *(Future)* Sidebar list of saved conversations |
| `WorkspaceView` | *(Future)* Workspace configuration and indexing status |

### View Model Layer

`ObservableObject` classes that coordinate between services and expose state to the UI.

| Component | Responsibility |
|---|---|
| `ChatViewModel` | Manages active conversation, agentic loop, model lifecycle |
| `ContextStore` | Manages context bubbles and system prompt persistence |
| `ModelCatalogService` | Fetches and caches model catalog from HF API |
| `ConversationManager` | *(Future)* CRUD for conversations, auto-save, search |
| `WorkspaceManager` | *(Future)* Workspace lifecycle, indexing orchestration |
| `SettingsStore` | *(Future)* Generation params, UI preferences, global config |

### Inference Engine

Protocols and implementations for running models locally.

| Protocol | Current Implementation | Future Implementations |
|---|---|---|
| `LLMService` | `LocalLLMServiceMLX` (real), `LocalLLMServiceStub` (fake) | `CloudLLMService` (OpenAI-compatible API) |
| `VLMService` | — | `LocalVLMServiceMLX` (MLXVLM) |
| `EmbeddingService` | — | `LocalEmbeddingServiceMLX` (MLXEmbedders) |

**Key design:** Each service protocol defines `load()`, `isLoaded`, and a generation/embedding method. The view model interacts only with the protocol, never with the concrete MLX types.

### Knowledge Layer

Components for document processing, embedding, and retrieval.

| Component | Responsibility |
|---|---|
| `EmbeddingService` | Generate vector embeddings from text chunks |
| `VectorIndex` | Store and query embeddings (k-nearest-neighbor search) |
| `DocumentLoader` | Read and parse files (Markdown, PDF, text, source code) |
| `ChunkSplitter` | Split documents into overlapping chunks (~512 tokens) |
| `SearchEngine` | Orchestrate: embed query → search index → rank results |

**Storage:** Vector indices are stored as binary files (a simple format of `[Float]` arrays) for fast memory-mapped loading. No external vector database dependency.

### Agent System

Components for tool registration, execution, and workflow management.

| Component | Responsibility |
|---|---|
| `AgentTool` (protocol) | Defines a tool's name, schema, and execution logic |
| `ToolRegistry` | Central registry of available tools |
| `ToolExecutor` | Parses tool calls from LLM output, validates, and executes |
| `ApprovalManager` | Manages user approval flow and persistent allow-list |
| `WorkflowEngine` | *(Future)* Compose named multi-tool sequences |
| `PluginLoader` | *(Future)* Discover and load third-party tool bundles |

---

## Concurrency Model

```
Main Actor (UI)
├── ChatViewModel        @MainActor
├── ContextStore         @MainActor
├── ModelCatalogService  @MainActor
├── ToolRegistry         @MainActor
│
├── Inference Task        (structured Task, cancellable)
│   └── LLMService.generateReplyStreaming()
│       └── Streams tokens back to @MainActor via callback
│
├── Indexing Task          (structured Task, cancellable)
│   └── EmbeddingService.indexDocuments()
│       └── Reports progress back to @MainActor
│
└── Tool Execution Task    (structured Task, cancellable)
    └── ToolExecutor.execute()
        └── Returns ToolResult to @MainActor
```

**Rules:**
- All `@Published` state lives on `@MainActor`
- Inference, indexing, and tool execution run in structured `Task` blocks
- Cancellation is cooperative: `Task.checkCancellation()` at yield points
- No detached tasks — everything is structured for clean cancellation

---

## Integration Patterns

### Model Loading

```swift
// Protocol
protocol LLMService {
    var isLoaded: Bool { get }
    func load() async throws
    func generateReplyStreaming(...) async throws
    func cancelGeneration()
}

// Usage in ViewModel (backend-agnostic)
await llmService.load()
try await llmService.generateReplyStreaming(from: messages, systemPrompt: prompt) { token in
    self.messages[idx].text += token
}
```

### Tool Registration

```swift
// Any new tool: implement AgentTool, register in ToolRegistry
struct MyNewTool: AgentTool {
    var name = "my_tool"
    var toolDescription = "Does something useful"
    var parameters: [ToolParameter] = [...]
    var requiresApproval = true
    var riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        // implementation
    }
}

// Registration
ToolRegistry.shared.register(MyNewTool())
```

### RAG Injection (Future)

```swift
// In ChatViewModel.send(), before composing the system prompt:
let queryEmbedding = try await embeddingService.embed(userMessage)
let results = vectorIndex.search(queryEmbedding, topK: 5)
let ragContext = results.map { "[\($0.sourceURL.lastPathComponent)] \($0.text)" }
                        .joined(separator: "\n\n")

let systemPrompt = contextStore.composedSystemPrompt
    + "\n\n[Retrieved Context]\n" + ragContext
```

---

## Technology Stack

| Layer | Technology | Notes |
|---|---|---|
| UI | SwiftUI | macOS 14.0+ |
| State management | ObservableObject / @Published | Combine for debounced auto-save |
| LLM inference | MLX Swift / MLXLLM | Quantized models on Metal GPU |
| VLM inference | MLXVLM | *(Future)* Vision-language models |
| Embeddings | MLXEmbedders | *(Future)* Local embedding generation |
| Persistence | JSON files / UserDefaults | File-based, no database |
| Vector storage | Custom binary format | Memory-mapped for fast search |
| Networking | URLSession | HF API only (model catalog + download) |
| Process management | Foundation.Process | Shell command execution for agent tools |
| macOS integration | AppKit interop (NSPasteboard, NSWorkspace) | Clipboard, app launching |

---

## Security Boundaries

```
┌─────────────────────────────────────────────┐
│ App Sandbox                                  │
│                                              │
│  ┌─────────────────────┐                     │
│  │ User-Approved Scope  │                     │
│  │                     │                     │
│  │ • Files the user    │  ┌────────────────┐ │
│  │   explicitly opened │  │ Always Allowed │ │
│  │ • Workspace dirs    │  │                │ │
│  │   via Open Panel    │  │ • App Support  │ │
│  │                     │  │ • Caches       │ │
│  └─────────────────────┘  │ • Network (HF) │ │
│                           │ • Clipboard    │ │
│  ┌─────────────────────┐  └────────────────┘ │
│  │ Gated by Approval   │                     │
│  │                     │                     │
│  │ • Shell commands    │                     │
│  │ • File writes       │                     │
│  │ • App launching     │                     │
│  └─────────────────────┘                     │
│                                              │
└─────────────────────────────────────────────┘
```

**Principle:** The sandbox defines the maximum possible access. The tool approval system provides a second layer of user-controlled gating within that sandbox.

---

*← [Features & Use Cases](VISION-04-features-and-use-cases.md) · Next: [Roadmap →](VISION-06-roadmap.md)*
