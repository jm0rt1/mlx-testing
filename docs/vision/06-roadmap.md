# 6 — Roadmap

This document defines a phased delivery plan for the MLX Copilot vision. Each phase builds on the previous one and includes concrete milestones, deliverables, and success criteria.

---

## Phase Overview

```
  Phase 1          Phase 2           Phase 3           Phase 4
  Foundation       Continuity        Multimodal        OS Companion
  (Current)        (Near-term)       Intelligence      (Long-term)
                                     
  ✅ Local LLM     ☐ Conversation    ☐ VLM support     ☐ Menu bar agent
  ✅ Model catalog    persistence    ☐ RAG pipeline    ☐ Global shortcut
  ✅ Context        ☐ Multi-convo    ☐ Document        ☐ Services integration
     bubbles       ☐ Metrics           indexing        ☐ Shortcuts actions
  ✅ Agentic        ☐ Gen params     ☐ Semantic        ☐ Auto-memory
     tools         ☐ Export            search          ☐ Plugin system
  ✅ Settings                        ☐ Citations
     persistence
                                     
  ─────────▶      ─────────▶        ─────────▶        ─────────▶
```

---

## Phase 1: Foundation ✅ (Current)

**Status:** Complete

**Summary:** The core chat application is functional with local LLM inference, model management, context composition, and agentic tool calling.

### Deliverables

| Deliverable | Status |
|---|---|
| Local LLM inference via MLX | ✅ |
| Streaming token output with cancellation | ✅ |
| Dynamic model catalog from HuggingFace API | ✅ |
| Runtime model switching with model picker | ✅ |
| Context bubbles (skill, instruction, memory, custom) | ✅ |
| System prompt editor with composed prompt preview | ✅ |
| Agentic tool system with approval flow | ✅ |
| Built-in tools (file system, shell, clipboard, app launcher) | ✅ |
| Persistent settings (context, system prompt, model selection) | ✅ |
| Stub backend for UI development | ✅ |

---

## Phase 2: Continuity

**Goal:** Make the app a daily-driver by preserving state across sessions and giving users control over generation behavior.

**Prerequisites:** Phase 1 complete.

### Milestone 2.1 — Conversation Persistence

**Deliverables:**
- `ConversationManager` class for CRUD operations on conversations
- JSON-based storage in `~/Library/Application Support/mlx-testing/conversations/`
- Auto-save with debounce (reuse `ContextStore` pattern)
- App restart restores all conversations
- Active conversation shown on relaunch

**Success Criteria:**
- Close and reopen the app → all conversations intact
- 100 conversations with 50 messages each load in < 1 second

### Milestone 2.2 — Multi-Conversation Management

**Deliverables:**
- Conversation list in sidebar (above or replacing context bubble editor)
- New Conversation button
- Rename, delete, archive via context menu
- Search conversations by title
- Most-recent-first sort order

**Success Criteria:**
- User can maintain 10+ concurrent conversations
- Switching between conversations is instantaneous

### Milestone 2.3 — Performance Metrics

**Deliverables:**
- `GenerationMetrics` struct captured during inference
- Tokens-per-second live counter in status bar during generation
- Post-generation metrics attached to assistant messages
- Metrics displayed as subtle footer text on message bubbles

**Success Criteria:**
- Metrics displayed with < 100ms update latency
- Accuracy within ±5% of actual throughput

### Milestone 2.4 — Generation Parameter Controls

**Deliverables:**
- Settings popover or panel accessible from toolbar
- Temperature slider (0.0–2.0)
- Top-p slider (0.0–1.0)
- Max tokens stepper (128–8192)
- Parameters saved to UserDefaults

**Success Criteria:**
- Changing temperature produces observably different outputs
- Settings persist across app restarts

### Milestone 2.5 — Conversation Export

**Deliverables:**
- Export as Markdown (formatted with headers, code blocks)
- Export as JSON (machine-readable, includes metadata)
- macOS save panel for file location
- Context menu and keyboard shortcut (⌘E)

**Success Criteria:**
- Exported Markdown renders correctly in GitHub/VS Code preview
- JSON re-importable (forward-compatibility)

---

## Phase 3: Multimodal Intelligence

**Goal:** Extend the AI's perception to images and documents, enabling vision understanding and knowledge-grounded responses.

**Prerequisites:** Phase 2 milestones 2.1–2.3 complete.

### Milestone 3.1 — Vision Language Model Support

**Deliverables:**
- `VLMService` protocol mirroring `LLMService` with image input
- `LocalVLMServiceMLX` implementation using MLXVLM
- Model picker distinguishes text-only vs. vision models
- Image attachment via drag-and-drop and paste (⌘V)
- Image thumbnails in chat bubbles

**Success Criteria:**
- User can paste a screenshot and get a meaningful description
- VLM streaming works with same UX as text LLM
- At least 3 VLM models available in the catalog

### Milestone 3.2 — Screenshot Capture

**Deliverables:**
- Camera button in input bar
- Integration with `CGWindowListCreateImage` or `ScreenCaptureKit`
- Region selection overlay
- Captured image becomes an ImageAttachment

**Success Criteria:**
- Capture-to-send in < 3 user actions
- Works across all screens and Spaces

### Milestone 3.3 — RAG Pipeline: Indexing

**Deliverables:**
- `EmbeddingService` protocol + `LocalEmbeddingServiceMLX` implementation
- `DocumentLoader` supporting Markdown, plain text, PDF, Swift/Python/JS source
- `ChunkSplitter` with ~512-token chunks and 64-token overlap
- `VectorIndex` with cosine similarity search
- Binary persistence for vector index
- Workspace UI for selecting directories and triggering indexing
- Progress reporting during indexing

**Success Criteria:**
- Index 1,000 Markdown files in < 60 seconds (M1 Pro)
- Index persists across app restarts
- Re-indexing only processes changed files (FSEvents)

### Milestone 3.4 — RAG Pipeline: Retrieval & Citations

**Deliverables:**
- Query embedding + top-k search integrated into `ChatViewModel.send()`
- RAG context injected into system prompt as `[Retrieved Context]` section
- `Citation` model with source file, excerpt, and relevance score
- Clickable citation badges on assistant messages
- Toggle RAG on/off per conversation

**Success Criteria:**
- Queries return relevant chunks for 80%+ of in-scope questions
- Search latency < 200ms for 10K-chunk index
- Citations accurately point to source files

---

## Phase 4: OS Companion

**Goal:** Transform MLX Copilot from a standalone app into a system-wide AI layer for macOS.

**Prerequisites:** Phase 3 milestones 3.1 and 3.3–3.4 complete.

### Milestone 4.1 — Menu Bar Agent

**Deliverables:**
- Menu bar icon (NSStatusItem)
- Compact floating panel with text input and response area
- Quick-access without switching to main window
- Conversations from menu bar logged in main app

**Success Criteria:**
- Summon panel in < 500ms
- Panel dismisses cleanly on Escape or click-away
- Works alongside full-screen apps

### Milestone 4.2 — Global Keyboard Shortcut

**Deliverables:**
- Configurable global shortcut (default: ⌥Space)
- Summons menu bar panel or main window
- Works in any app context

**Success Criteria:**
- Shortcut registered system-wide
- No conflicts with default macOS shortcuts
- User can customize via Settings

### Milestone 4.3 — macOS Services Integration

**Deliverables:**
- NSServices provider for text processing
- "Ask MLX Copilot", "Summarize with MLX Copilot" in Services menu
- Result displayed in floating panel or inserted back into source app

**Success Criteria:**
- Services appear in right-click menu of all text-capable apps
- Round-trip (select → invoke → result) in < 5 seconds

### Milestone 4.4 — Shortcuts App Actions

**Deliverables:**
- App Intent definitions: "Ask LLM", "Search Documents", "Generate Embedding"
- Shortcuts integration via `AppIntents` framework
- Parameterized inputs and structured outputs

**Success Criteria:**
- Actions discoverable in Shortcuts app
- Composable with other Shortcuts actions
- Runs headlessly (no window required)

### Milestone 4.5 — Automatic Memory Extraction

**Deliverables:**
- Post-conversation summarization prompt
- Extracted facts → new `.memory` ContextBubbles
- User notification of new memories
- Review/edit/delete flow in Context sidebar

**Success Criteria:**
- Extracts 1–3 relevant facts per substantial conversation
- No duplicate memories (deduplication by semantic similarity)
- User retains full control over all stored memories

### Milestone 4.6 — Plugin System

**Deliverables:**
- Plugin specification document
- Plugin loader that discovers `.bundle` files in plugin directory
- Sandboxed execution context for third-party tools
- Plugin management UI (enable/disable/remove)

**Success Criteria:**
- Third-party developer can create and distribute a tool plugin
- Plugins cannot access data outside their sandbox without approval
- Loading a plugin does not require app restart

---

## Dependency Graph

```
Phase 1 (Foundation) ──────────┐
          ✅ Complete           │
                               ▼
                    Phase 2 (Continuity)
                    ├── 2.1 Conversation Persistence
                    ├── 2.2 Multi-Conversation
                    ├── 2.3 Performance Metrics
                    ├── 2.4 Generation Parameters
                    └── 2.5 Conversation Export
                               │
              ┌────────────────┤
              ▼                ▼
    Phase 3 (Multimodal)     Phase 4 (OS Companion)
    ├── 3.1 VLM Support      ├── 4.1 Menu Bar Agent
    ├── 3.2 Screenshots       ├── 4.2 Global Shortcut
    │   (requires 3.1)        │   (requires 4.1)
    ├── 3.3 RAG Indexing      ├── 4.3 Services
    └── 3.4 RAG Retrieval     ├── 4.4 Shortcuts
        (requires 3.3)        ├── 4.5 Auto-Memory
                               │   (requires 3.3)
                               └── 4.6 Plugin System
```

**Note:** Phase 3 and Phase 4 have some independent milestones and can be partially developed in parallel. For example, 4.1 (Menu Bar Agent) does not depend on any Phase 3 work, while 4.5 (Auto-Memory) depends on embedding capabilities from 3.3.

---

## Risk Register

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| VLM models too large for 16 GB Macs | High | Medium | Prioritize small VLMs (e.g., LLaVA-1.5 7B 4-bit), show RAM warnings |
| MLX Swift API breaking changes | Medium | Medium | Pin dependency versions, abstract behind protocols |
| Vector index grows too large for file-based storage | Medium | Low | Implement sharding, consider SQLite FTS5 as fallback |
| macOS sandbox blocks desired file access | High | Medium | Use Security-Scoped Bookmarks, document required entitlements early |
| Plugin system introduces security vulnerabilities | High | Medium | Sandbox plugins, require code signing, manual review process |
| User confusion between text and vision models | Low | High | Clear model badges, auto-detect image input capability |

---

## Success Metrics

| Metric | Phase 2 Target | Phase 3 Target | Phase 4 Target |
|---|---|---|---|
| Daily active use (self-measured) | App opened daily | Replaces web search for local docs | First tool summoned via shortcut |
| Conversations per week | 10+ persisted | 5+ with RAG citations | 20+ (including menu bar quick chats) |
| Tool calls per week | 5+ | 10+ (including RAG search) | 30+ (across all integration surfaces) |
| Time to answer (user-perceived) | < 5 sec | < 8 sec (with RAG) | < 3 sec (menu bar quick queries) |

---

*← [Architecture](05-architecture.md) · Back to [Vision Index](README.md)*
