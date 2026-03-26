# 2 — Requirements

This document defines the functional requirements (FR), non-functional requirements (NFR), and constraints for the MLX Copilot vision.

Requirements are grouped by capability area and prioritized using **MoSCoW** (Must / Should / Could / Won't).

---

## Constraints

| ID | Constraint | Rationale |
|---|---|---|
| C-1 | macOS 14.0+ on Apple Silicon (M1 or later) | MLX requires Metal GPU and unified memory |
| C-2 | Swift 5.10+ / Xcode 16.0+ | Modern concurrency, SwiftUI features |
| C-3 | No mandatory cloud services | Core privacy guarantee |
| C-4 | App Sandbox with minimal entitlement expansion | macOS distribution and security best practice |
| C-5 | Minimum 16 GB unified memory (24 GB+ recommended) | Required for useful model sizes |

---

## Functional Requirements

### FR-1 — Local LLM Inference

| ID | Requirement | Priority | Status |
|---|---|---|---|
| FR-1.1 | Run quantized LLMs (1B–30B) on-device via MLX | Must | ✅ Done |
| FR-1.2 | Stream token output in real time | Must | ✅ Done |
| FR-1.3 | Cancel generation mid-reply (⌘.) | Must | ✅ Done |
| FR-1.4 | Display tokens-per-second performance metrics | Should | ☐ Planned |
| FR-1.5 | Support configurable generation parameters (temperature, top-p, max tokens) | Should | ☐ Partial |
| FR-1.6 | Hot-swap models at runtime without restarting | Must | ✅ Done |
| FR-1.7 | Fall back to stub backend for UI development | Must | ✅ Done |

### FR-2 — Vision Language Models (VLM)

| ID | Requirement | Priority | Status |
|---|---|---|---|
| FR-2.1 | Load and run VLMs (e.g., LLaVA, Qwen-VL) via MLXVLM | Must | ☐ Planned |
| FR-2.2 | Accept image input via drag-and-drop or paste | Must | ☐ |
| FR-2.3 | Accept screenshot capture from within the app | Should | ☐ |
| FR-2.4 | Display image thumbnails inline in chat bubbles | Must | ☐ |
| FR-2.5 | Support multi-image conversations | Could | ☐ |

### FR-3 — Retrieval-Augmented Generation (RAG)

| ID | Requirement | Priority | Status |
|---|---|---|---|
| FR-3.1 | Generate embeddings from local documents via MLXEmbedders | Must | ☐ Planned |
| FR-3.2 | Build and persist a local vector index (per-workspace or global) | Must | ☐ |
| FR-3.3 | Semantic search across indexed documents | Must | ☐ |
| FR-3.4 | Automatically inject top-k relevant chunks into the system prompt | Must | ☐ |
| FR-3.5 | Support incremental re-indexing when files change (FSEvents) | Should | ☐ |
| FR-3.6 | Support PDF, Markdown, plain text, and source code file types | Must | ☐ |
| FR-3.7 | Display source citations with links to original documents | Should | ☐ |

### FR-4 — Agentic Tool System

| ID | Requirement | Priority | Status |
|---|---|---|---|
| FR-4.1 | Extensible tool protocol with name, schema, and execute method | Must | ✅ Done |
| FR-4.2 | Tool registry with runtime registration and discovery | Must | ✅ Done |
| FR-4.3 | Parse tool calls from LLM output (JSON in fenced blocks) | Must | ✅ Done |
| FR-4.4 | Agentic loop: generate → parse → approve → execute → feed back → repeat | Must | ✅ Done |
| FR-4.5 | User approval flow with approve / deny / always-approve options | Must | ✅ Done |
| FR-4.6 | Risk-level classification (low / medium / high) per tool | Must | ✅ Done |
| FR-4.7 | Built-in tools: file system, shell, clipboard, app launcher | Must | ✅ Done |
| FR-4.8 | Tool result display with artifacts (file paths, code, URLs) | Must | ✅ Done |
| FR-4.9 | Plugin system: load third-party tools from bundles or scripts | Could | ☐ |
| FR-4.10 | Workflow orchestration: compose multi-tool sequences as named workflows | Could | ☐ |

### FR-5 — Context & Memory

| ID | Requirement | Priority | Status |
|---|---|---|---|
| FR-5.1 | Toggleable context bubbles (skill, instruction, memory, custom) | Must | ✅ Done |
| FR-5.2 | Compose system prompt from base prompt + enabled bubbles | Must | ✅ Done |
| FR-5.3 | Persist context bubbles and base prompt to disk | Must | ✅ Done |
| FR-5.4 | Persist full conversation history across sessions | Must | ☐ Planned |
| FR-5.5 | Multiple named conversations with sidebar navigation | Should | ☐ |
| FR-5.6 | Automatic memory extraction: summarize conversations into memory bubbles | Could | ☐ |
| FR-5.7 | Project-scoped context: bind context sets to directories/workspaces | Should | ☐ |
| FR-5.8 | Conversation search (full-text and semantic) | Could | ☐ |

### FR-6 — Model Management

| ID | Requirement | Priority | Status |
|---|---|---|---|
| FR-6.1 | Dynamic model catalog fetched from HuggingFace API | Must | ✅ Done |
| FR-6.2 | Model picker with search, download status, size info | Must | ✅ Done |
| FR-6.3 | Download progress tracking in status bar | Must | ✅ Done |
| FR-6.4 | Delete downloaded models to reclaim disk space | Must | ✅ Done |
| FR-6.5 | Display per-model memory usage and compatibility warnings | Should | ☐ Partial |
| FR-6.6 | Support loading custom/fine-tuned models from local paths | Should | ☐ |
| FR-6.7 | Model comparison: run the same prompt against multiple models | Could | ☐ |

### FR-7 — macOS Integration

| ID | Requirement | Priority | Status |
|---|---|---|---|
| FR-7.1 | Menu bar quick-access (floating prompt anywhere in macOS) | Should | ☐ |
| FR-7.2 | Global keyboard shortcut to summon the assistant | Should | ☐ |
| FR-7.3 | macOS Services integration (process selected text in any app) | Could | ☐ |
| FR-7.4 | Shortcuts app actions (Siri Shortcuts integration) | Could | ☐ |
| FR-7.5 | Accessibility API integration for screen reading and UI automation | Could | ☐ |

---

## Non-Functional Requirements

### NFR-1 — Performance

| ID | Requirement | Target |
|---|---|---|
| NFR-1.1 | Time to first token (8B 4-bit model, 24 GB Mac) | < 2 seconds |
| NFR-1.2 | Sustained generation throughput | ≥ 30 tokens/sec for 4-bit 8B models |
| NFR-1.3 | App launch to interactive | < 3 seconds (model loads in background) |
| NFR-1.4 | Embedding generation throughput | ≥ 500 chunks/sec for short passages |
| NFR-1.5 | Semantic search latency (10K document index) | < 200 ms |

### NFR-2 — Privacy & Security

| ID | Requirement | Target |
|---|---|---|
| NFR-2.1 | Zero network calls when operating offline | All features functional without internet |
| NFR-2.2 | No telemetry or analytics data collection | Verified by absence of tracking code |
| NFR-2.3 | Sandboxed execution for all agent tools | User-scoped file access only, no root |
| NFR-2.4 | Tool execution gated by approval system | Default: all medium/high risk tools require approval |
| NFR-2.5 | Conversation and context data encrypted at rest | macOS Data Protection / FileVault |

### NFR-3 — Usability

| ID | Requirement | Target |
|---|---|---|
| NFR-3.1 | Fully keyboard-navigable (no mouse required) | All primary flows accessible via keyboard |
| NFR-3.2 | VoiceOver accessible | Standard SwiftUI accessibility support |
| NFR-3.3 | Dark mode and light mode support | Automatic via system appearance |
| NFR-3.4 | Resizable window with responsive layout | Min 700×500, scales to ultrawide |

### NFR-4 — Reliability

| ID | Requirement | Target |
|---|---|---|
| NFR-4.1 | Graceful degradation on low memory | Warn user, suggest smaller model |
| NFR-4.2 | No data loss on crash | Auto-save with ≤ 1 second debounce |
| NFR-4.3 | Agentic loop iteration cap | Max 10 iterations to prevent runaway |

---

*← [Concept](01-concept.md) · Next: [Domain Model →](03-domain-model.md)*
