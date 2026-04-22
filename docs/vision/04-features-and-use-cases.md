# 4 — Features & Use Cases

This document catalogs the planned features, maps them to user stories, and provides detailed use case narratives. Features are organized into capability tiers that align with the [Roadmap](06-roadmap.md) phases.

---

## Feature Map

```
                            MLX Copilot Features
    ┌────────────────────────────────────────────────────────────┐
    │                                                            │
    │  Tier 1: Foundation (Current)                              │
    │  ├── Local LLM chat with streaming                         │
    │  ├── Model catalog and runtime model switching              │
    │  ├── Context bubbles and system prompt composition          │
    │  ├── Agentic tool calling with approval flow                │
    │  └── Persistent settings                                   │
    │                                                            │
    │  Tier 2: Continuity                                        │
    │  ├── Conversation persistence and history                   │
    │  ├── Multi-conversation management                          │
    │  ├── Performance metrics (tokens/sec)                       │
    │  ├── Generation parameter controls                          │
    │  └── Conversation export (Markdown, JSON)                   │
    │                                                            │
    │  Tier 3: Multimodal Intelligence                            │
    │  ├── Vision language model support (VLM)                    │
    │  ├── Image input (paste, drag-drop, screenshot)             │
    │  ├── RAG pipeline with local embeddings                     │
    │  ├── Workspace-scoped document indexing                      │
    │  └── Semantic search with citations                         │
    │                                                            │
    │  Tier 4: OS Companion                                      │
    │  ├── Menu bar agent (global quick-access)                   │
    │  ├── Global keyboard shortcut                               │
    │  ├── macOS Services integration                             │
    │  ├── Shortcuts app actions                                  │
    │  ├── Auto-memory extraction from conversations              │
    │  └── Plugin system for third-party tools                    │
    │                                                            │
    └────────────────────────────────────────────────────────────┘
```

---

## Tier 1: Foundation (Current State)

### F-1.1 Local LLM Chat

**User Story:** As a user, I want to chat with an AI that runs entirely on my Mac so that I can get help without sending data to the cloud.

**Current Implementation:**
- `LocalLLMServiceMLX` loads quantized models via `LLMModelFactory`
- `ChatViewModel` manages the message list and streaming loop
- `ContentView` renders chat bubbles with scroll-to-bottom
- Stub backend available for UI development

### F-1.2 Model Catalog & Picker

**User Story:** As a user, I want to browse available models, see their sizes, and switch between them at runtime so I can choose the best model for my hardware and task.

**Current Implementation:**
- `ModelCatalogService` fetches model metadata from the HuggingFace API
- `ModelPickerView` presents a searchable popover with download status, size, and parameter info
- `ModelInfo` tracks local download state and estimated RAM usage

### F-1.3 Context Bubbles

**User Story:** As a user, I want to define reusable context snippets (skills, instructions, memories) that are automatically composed into the system prompt, so the AI stays aligned with my preferences across conversations.

**Current Implementation:**
- `ContextBubble` model with four types: skill, instruction, memory, custom
- `ContextBubbleEditor` sidebar for CRUD operations
- `ContextStore` persists to `~/Library/Application Support/mlx-testing/`
- Auto-save with 1-second debounce

### F-1.4 Agentic Tool Calling

**User Story:** As a power user, I want the AI to read files, run commands, and interact with my system on my behalf, so I can accomplish complex tasks through conversation.

**Current Implementation:**
- `AgentTool` protocol with `ToolRegistry`, `ToolExecutor`
- Built-in tools: `FileSystemTool`, `ShellCommandTool`, `ClipboardTool`, `AppLauncherTool`
- Agentic loop in `ChatViewModel` with max 10 iterations
- User approval flow with approve / deny / always-approve

---

## Tier 2: Continuity

### F-2.1 Conversation Persistence

**User Story:** As a user, I want my conversations to be saved automatically and available when I reopen the app, so I don't lose context.

**Use Case Narrative:**

1. User opens the app and sees a list of past conversations in the sidebar
2. They select a previous conversation to continue it
3. New messages are streamed and auto-saved
4. If the app crashes, the conversation is recovered from the last saved state

**Entities involved:** Conversation, ChatMessage, ContextStore

**Acceptance Criteria:**
- Conversations are saved to disk within 2 seconds of any change
- App restart restores all conversations with full message history
- Conversations are stored as human-readable JSON

### F-2.2 Multi-Conversation Management

**User Story:** As a user, I want to maintain multiple separate conversations with different topics, rename them, and archive or delete old ones.

**Use Case Narrative:**

1. User clicks "New Conversation" in the sidebar
2. A new conversation starts with a fresh context
3. They can switch between conversations without losing state
4. Right-clicking a conversation offers Rename, Export, and Delete

**Entities involved:** Conversation, ChatViewModel

**Acceptance Criteria:**
- Sidebar displays conversation list sorted by most recent
- Switching conversations preserves the message history of both
- Deleting a conversation removes it from disk

### F-2.3 Performance Metrics

**User Story:** As a user, I want to see how fast the model is generating tokens so I can evaluate model performance and make informed model choices.

**Use Case Narrative:**

1. User sends a message
2. During generation, the status bar shows "Generating… 42 tok/s"
3. After completion, the assistant message shows a subtle "128 tokens · 38 tok/s · 3.4s" footer

**Entities involved:** GenerationMetrics, ChatMessage, LLMService

**Acceptance Criteria:**
- Tokens-per-second updates live during generation
- Final metrics attached to the completed assistant message
- Metrics visible but unobtrusive (small text, muted color)

### F-2.4 Generation Parameter Controls

**User Story:** As a user, I want to adjust temperature, top-p, and max token count so I can control the creativity and length of responses.

**Use Case Narrative:**

1. User opens a settings panel from the toolbar
2. They adjust temperature slider (0.0–2.0), top-p (0.0–1.0), max tokens (128–8192)
3. Changes take effect on the next generation

**Entities involved:** GenerateParameters, ChatViewModel

### F-2.5 Conversation Export

**User Story:** As a user, I want to export a conversation as Markdown or JSON so I can share it, archive it, or process it externally.

**Use Case Narrative:**

1. User right-clicks a conversation → Export
2. Chooses format: Markdown or JSON
3. Selects save location via standard macOS save panel
4. File is written to disk

---

## Tier 3: Multimodal Intelligence

### F-3.1 Vision Language Model Support

**User Story:** As a user, I want to share images with the AI and ask questions about them, so I can get help understanding screenshots, diagrams, photos, and documents.

**Use Case Narrative:**

1. User drags an image into the chat input area (or pastes with ⌘V)
2. A thumbnail preview appears in the input bar
3. User types "What does this error message say?" and sends
4. The VLM processes both the image and text, and streams a response
5. The image thumbnail is displayed inline in the user's message bubble

**Entities involved:** ImageAttachment, ChatMessage, VLMService

**Acceptance Criteria:**
- Supports JPEG, PNG, HEIC image formats
- Images displayed as thumbnails (max 200px) in chat bubbles
- VLM models (LLaVA, Qwen-VL) loaded via MLXVLM framework
- Model picker distinguishes text-only vs. vision-capable models

### F-3.2 Screenshot Capture

**User Story:** As a user, I want to capture a region of my screen and immediately ask the AI about it, without leaving the app.

**Use Case Narrative:**

1. User clicks the camera icon in the input bar (or presses ⌘⇧4)
2. macOS screen capture overlay appears
3. User selects a region
4. The screenshot appears as an image attachment in the input bar
5. User sends it with a question

### F-3.3 RAG Pipeline — Document Indexing

**User Story:** As a user, I want to point the AI at a folder of documents so it can search them semantically and reference them in its answers.

**Use Case Narrative:**

1. User creates a new Workspace and selects a root directory (e.g., `~/Projects/my-app`)
2. The system scans for supported files (Markdown, text, PDF, source code)
3. Files are chunked and embedded using a local MLXEmbedders model
4. Progress is shown: "Indexing… 142/350 files"
5. The vector index is persisted to disk

**Entities involved:** Workspace, VectorIndex, DocumentChunk, EmbeddingService

**Acceptance Criteria:**
- Supports Markdown, plain text, PDF, and common source code files
- Chunking strategy: ~512 tokens per chunk with overlap
- Index persisted as a binary file for fast loading
- Incremental re-indexing when files change (FSEvents watcher)

### F-3.4 RAG Pipeline — Semantic Search

**User Story:** As a user, I want my questions to automatically search my indexed documents so the AI's answers are grounded in my actual data.

**Use Case Narrative:**

1. User asks: "How does the model loading work in LocalLLMService?"
2. The system embeds the query and searches the vector index
3. Top-5 relevant chunks are retrieved (with cosine similarity scores)
4. Chunks are injected into the system prompt as `[Retrieved Context]`
5. The AI's response references the actual code with inline citations
6. Citations appear as clickable links: "📄 LocalLLMService.swift:59–84"

**Entities involved:** VectorIndex, DocumentChunk, Citation, ChatMessage

**Acceptance Criteria:**
- Search returns results in < 200ms for a 10K-chunk index
- Citations link to the original file (opens in Finder or default editor)
- User can toggle RAG on/off per conversation

---

## Tier 4: OS Companion

### F-4.1 Menu Bar Agent

**User Story:** As a user, I want to access the AI from anywhere in macOS via a menu bar icon, so I can ask quick questions without switching to the full app.

**Use Case Narrative:**

1. MLX Copilot runs as a menu bar app (with optional main window)
2. User clicks the menu bar icon or presses the global shortcut
3. A compact floating panel appears with a text input
4. User types a question → gets a streaming response
5. The panel dismisses when the user clicks away or presses Escape
6. Full conversation is logged in the main app

### F-4.2 Global Keyboard Shortcut

**User Story:** As a user, I want a system-wide keyboard shortcut (e.g., ⌥Space) to summon the AI, so I can get help in any context.

### F-4.3 macOS Services Integration

**User Story:** As a user, I want to select text in any application, right-click, and choose "Ask MLX Copilot" from the Services menu to process that text through the AI.

**Use Case Narrative:**

1. User selects a paragraph in Safari, Notes, or any text-capable app
2. Right-click → Services → "Summarize with MLX Copilot"
3. MLX Copilot processes the text with a pre-configured prompt
4. Result is inserted back or displayed in a floating panel

### F-4.4 Shortcuts App Actions

**User Story:** As a user, I want to create Shortcuts automations that use MLX Copilot as a processing step, so I can integrate local AI into my workflows.

**Use Case Narrative:**

1. User opens the Shortcuts app
2. They find "MLX Copilot" actions: "Ask LLM", "Search Documents", "Generate Embedding"
3. They create a Shortcut: "When I save a PDF to Downloads → index it → summarize it → save summary to Notes"
4. The Shortcut runs locally, using MLX Copilot's inference engine

### F-4.5 Auto-Memory Extraction

**User Story:** As a user, I want the AI to automatically remember important facts from our conversations, so it gets better at helping me over time.

**Use Case Narrative:**

1. During a conversation, the user mentions "I'm working on the MLX Copilot project and I prefer protocol-oriented design"
2. At the end of the conversation (or periodically), the system runs a memory extraction prompt
3. The extracted facts become new ContextBubbles of type `.memory`
4. User is notified: "📝 2 new memories saved — review in Context sidebar"
5. User can edit, disable, or delete auto-extracted memories

**Entities involved:** ContextBubble, ContextStore, ChatViewModel

### F-4.6 Plugin System

**User Story:** As a developer, I want to create and distribute custom tools that extend MLX Copilot's capabilities, without modifying the core app.

**Use Case Narrative:**

1. Developer creates a Swift package conforming to the `AgentTool` protocol
2. They build it as a `.bundle` and place it in `~/Library/Application Support/mlx-testing/plugins/`
3. On launch, MLX Copilot discovers and loads the plugin
4. The new tool appears in the tool registry and is available to the LLM
5. The plugin runs in a sandboxed context with limited system access

---

## Cross-Cutting Concerns

### Offline Operation

All Tier 1–3 features must work without internet access once models are downloaded. The only features requiring network are:
- Initial model download from HuggingFace
- Model catalog refresh

### Data Migration

As the persistence model evolves, each schema change must include a migration path:
- Version-stamped JSON files
- Forward-compatible decoders
- First-launch migration from previous format

### Accessibility

All new UI must include:
- VoiceOver labels for all interactive elements
- Keyboard navigation (Tab, Enter, Escape)
- Dynamic Type support where applicable
- Reduced Motion respect for animations

---

*← [Domain Model](03-domain-model.md) · Next: [Architecture →](05-architecture.md)*
