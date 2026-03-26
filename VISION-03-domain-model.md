# 3 — Domain Model

This document defines the core entities, their relationships, and the data flows that make up the MLX Copilot system. It establishes a shared vocabulary for all other vision documents.

---

## Entity Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          MLX Copilot                                │
│                                                                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐    │
│  │ Conversation  │   │ Model        │   │ Context              │    │
│  │   Manager     │   │   Manager    │   │   Manager            │    │
│  │              │   │              │   │                      │    │
│  │ Conversation │   │ ModelInfo    │   │ ContextBubble        │    │
│  │ ChatMessage  │   │ ModelCatalog │   │ ContextStore         │    │
│  │ MessageRole  │   │ ModelConfig  │   │ SystemPrompt         │    │
│  └──────┬───────┘   └──────┬───────┘   └──────────┬───────────┘    │
│         │                  │                       │                │
│         ▼                  ▼                       ▼                │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                     Inference Engine                         │    │
│  │                                                             │    │
│  │  LLMService ──▶ LocalLLMServiceMLX / LocalLLMServiceStub   │    │
│  │  VLMService ──▶ (future: LocalVLMServiceMLX)               │    │
│  │  EmbeddingService ──▶ (future: LocalEmbeddingServiceMLX)   │    │
│  └──────────────────────────┬──────────────────────────────────┘    │
│                             │                                       │
│         ┌───────────────────┼───────────────────┐                   │
│         ▼                   ▼                   ▼                   │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐    │
│  │ Agent        │   │ RAG          │   │ macOS                │    │
│  │   System     │   │   Pipeline   │   │   Integration        │    │
│  │              │   │              │   │                      │    │
│  │ AgentTool    │   │ VectorIndex  │   │ MenuBarAgent         │    │
│  │ ToolRegistry │   │ DocumentChunk│   │ GlobalShortcut       │    │
│  │ ToolExecutor │   │ SearchResult │   │ ServicesProvider      │    │
│  │ ToolCall     │   │ Workspace    │   │ ShortcutsAction      │    │
│  │ ToolResult   │   │              │   │                      │    │
│  └──────────────┘   └──────────────┘   └──────────────────────┘    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Core Entities

### Conversation

A conversation is a sequence of messages between the user and the assistant within a single session.

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Unique conversation identifier |
| `title` | String | User-editable or auto-generated title |
| `messages` | [ChatMessage] | Ordered list of messages |
| `createdAt` | Date | When the conversation started |
| `updatedAt` | Date | Last message timestamp |
| `modelID` | String | HuggingFace model ID used |
| `contextSnapshot` | [UUID] | IDs of context bubbles active when created |

**Relationships:**
- A Conversation contains many ChatMessages (1:N)
- A Conversation is associated with one Model (N:1)
- A Conversation may reference many ContextBubbles (N:M)

### ChatMessage

A single message in a conversation. Today supports text; will be extended for images, tool calls, and structured data.

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Unique message identifier |
| `role` | Role | `.user`, `.assistant`, `.system`, `.toolCall`, `.toolResult` |
| `text` | String | Message content (Markdown-capable) |
| `date` | Date | When the message was created |
| `images` | [ImageAttachment]? | *(Future)* Attached images for VLM input |
| `toolCall` | ToolCallInfo? | Parsed tool invocation metadata |
| `toolResult` | ToolResultInfo? | Tool execution result metadata |
| `citations` | [Citation]? | *(Future)* RAG source references |
| `metrics` | GenerationMetrics? | *(Future)* Tokens/sec, token count |

### ModelInfo

Metadata about an available LLM, fetched from the HuggingFace API and cached locally.

| Field | Type | Description |
|---|---|---|
| `id` | String | HuggingFace repo ID (e.g., `mlx-community/Qwen3-8B-4bit`) |
| `modelType` | String | Architecture (e.g., `qwen3`, `llama`) |
| `quantizationBits` | Int? | Quantization level (4, 8, etc.) |
| `storageSizeBytes` | Int64 | Total weight file size on HF |
| `downloads` | Int | HF download count |
| `likes` | Int | HF likes count |
| `tags` | [String] | HF tags |
| `lastFetched` | Date | When this entry was last refreshed |
| `isDownloaded` | Bool | Whether weights are cached locally |

### ContextBubble

A toggleable block of context that is composed into the system prompt.

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Unique bubble identifier |
| `name` | String | Display name (e.g., "Swift Expert") |
| `content` | String | The context text injected into the prompt |
| `type` | BubbleType | `.skill`, `.instruction`, `.memory`, `.custom` |
| `isEnabled` | Bool | Whether this bubble is active |
| `createdAt` | Date | Creation timestamp |
| `updatedAt` | Date | Last modified timestamp |
| `workspaceID` | UUID? | *(Future)* Scope to a specific workspace |

### AgentTool

A capability that the LLM can invoke to interact with the user's environment.

| Field | Type | Description |
|---|---|---|
| `name` | String | Unique tool identifier (e.g., `read_file`) |
| `toolDescription` | String | Human-readable description for the LLM |
| `parameters` | [ToolParameter] | JSON-Schema-style parameter definitions |
| `requiresApproval` | Bool | Whether user must approve before execution |
| `riskLevel` | ToolRiskLevel | `.low`, `.medium`, `.high` |

### ToolCall

A parsed tool invocation from the LLM's output.

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Unique call identifier |
| `toolName` | String | Which tool to invoke |
| `arguments` | [String: ToolArgumentValue] | Arguments parsed from JSON |

### ToolResult

The outcome of executing a tool.

| Field | Type | Description |
|---|---|---|
| `toolName` | String | Which tool was executed |
| `success` | Bool | Whether execution succeeded |
| `output` | String | Human-readable output |
| `artifacts` | [ToolArtifact] | Produced files, URLs, code snippets |

---

## Future Entities

These entities do not exist in the codebase today but are required by the vision.

### Workspace

A scoped project context that binds together a directory, a set of context bubbles, a vector index, and conversation history.

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Unique workspace identifier |
| `name` | String | Display name (e.g., "mlx-testing project") |
| `rootPath` | URL | Root directory on disk |
| `contextBubbleIDs` | [UUID] | Context bubbles scoped to this workspace |
| `vectorIndexID` | UUID? | Associated RAG vector index |
| `defaultModelID` | String? | Preferred model for this workspace |

### VectorIndex

A persistent local embedding index for semantic search.

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Unique index identifier |
| `name` | String | Display name |
| `embeddingModelID` | String | HF model used to generate embeddings |
| `chunkCount` | Int | Number of indexed chunks |
| `sourcePaths` | [URL] | Directories/files being indexed |
| `lastIndexed` | Date | Last re-index timestamp |

### DocumentChunk

A segment of a document stored in the vector index.

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Unique chunk identifier |
| `sourceURL` | URL | Original file path |
| `text` | String | Chunk text content |
| `embedding` | [Float] | Embedding vector |
| `startOffset` | Int | Character offset in source file |
| `endOffset` | Int | End character offset |
| `metadata` | [String: String] | File type, heading, etc. |

### Citation

A reference from a RAG-augmented response back to its source document.

| Field | Type | Description |
|---|---|---|
| `chunkID` | UUID | Which chunk was referenced |
| `sourceURL` | URL | Original file path |
| `relevanceScore` | Float | Cosine similarity score |
| `excerpt` | String | Relevant text snippet |

### ImageAttachment

An image attached to a chat message for VLM processing.

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Unique attachment identifier |
| `data` | Data | Image data (JPEG/PNG) |
| `thumbnail` | Data | Downscaled preview for UI display |
| `sourceType` | SourceType | `.paste`, `.dragDrop`, `.screenshot`, `.file` |
| `caption` | String? | Optional user-provided description |

### GenerationMetrics

Performance data captured during model inference.

| Field | Type | Description |
|---|---|---|
| `promptTokens` | Int | Number of tokens in the prompt |
| `completionTokens` | Int | Number of generated tokens |
| `tokensPerSecond` | Double | Sustained generation speed |
| `timeToFirstToken` | TimeInterval | Latency before first token |
| `totalDuration` | TimeInterval | Wall-clock generation time |

---

## Data Flow Diagrams

### Chat Flow (Current)

```
User Input
    │
    ▼
ChatViewModel.send()
    │
    ├──▶ Compose system prompt (ContextStore.composedSystemPrompt)
    │        + tool schemas (ToolRegistry.toolSchemaPrompt)
    │
    ├──▶ Append user ChatMessage
    │
    └──▶ Agentic Loop
             │
             ├──▶ LLMService.generateReplyStreaming()
             │        │
             │        └──▶ Stream tokens → update assistant ChatMessage
             │
             ├──▶ Parse ToolCall from response
             │        │
             │        ├── No tool call → Done
             │        │
             │        └── Tool call found:
             │              │
             │              ├──▶ Request user approval
             │              ├──▶ ToolExecutor.execute()
             │              ├──▶ Append ToolResult message
             │              └──▶ Loop back (generate again with tool result)
             │
             └──▶ (max 10 iterations)
```

### RAG-Augmented Chat Flow (Future)

```
User Input
    │
    ▼
ChatViewModel.send()
    │
    ├──▶ Generate query embedding (EmbeddingService)
    ├──▶ Search VectorIndex → top-k DocumentChunks
    ├──▶ Compose system prompt + context bubbles + RAG chunks
    │
    ├──▶ Append user ChatMessage
    │
    └──▶ Agentic Loop (same as above)
             │
             └──▶ Assistant response includes Citations
```

### VLM Chat Flow (Future)

```
User Input + Image(s)
    │
    ▼
ChatViewModel.send()
    │
    ├──▶ Encode images as ImageAttachments
    ├──▶ Compose multi-modal prompt
    │
    ├──▶ Append user ChatMessage (with images)
    │
    └──▶ VLMService.generateReplyStreaming(text:, images:)
             │
             └──▶ Stream tokens → update assistant ChatMessage
```

---

## Persistence Model

| Data | Storage | Format | Location |
|---|---|---|---|
| Context bubbles | File | JSON | `~/Library/Application Support/mlx-testing/contexts.json` |
| Base system prompt | File | Plain text | `~/Library/Application Support/mlx-testing/system_prompt.txt` |
| Model catalog | File | JSON | `~/Library/Application Support/mlx-testing/model_catalog.json` |
| Selected model | UserDefaults | String | Key: `selectedModelID` |
| Tool approvals | UserDefaults | [String] | Key: `tool_always_approved` |
| Conversations | *(Future)* File | JSON | `~/Library/Application Support/mlx-testing/conversations/` |
| Vector indices | *(Future)* File | Binary | `~/Library/Application Support/mlx-testing/indices/` |
| Model weights | Cache | Safetensors | `~/Library/Caches/models/` |

---

*← [Requirements](VISION-02-requirements.md) · Next: [Features & Use Cases →](VISION-04-features-and-use-cases.md)*
