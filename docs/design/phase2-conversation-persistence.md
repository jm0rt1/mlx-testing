# Conversation Persistence — Milestone 2.1

> Technical design for saving and restoring conversations across app sessions.

**Status:** Ready for implementation
**Milestone:** [2.1 — Conversation Persistence](../vision/06-roadmap.md)
**Requirements:** [FR-5.4](../vision/02-requirements.md), [FR-5.5](../vision/02-requirements.md)

---

## Overview

Today, conversations are ephemeral — closing the app loses all chat history. This design adds automatic persistence so conversations survive app restarts, and introduces a `ConversationManager` to handle CRUD operations and future multi-conversation support.

## Goals

- Save conversations automatically as messages are added
- Restore the active conversation on app launch
- Lay the foundation for multi-conversation management (Milestone 2.2)
- Maintain human-readable storage format for inspectability

## Non-Goals

- Multi-conversation sidebar UI (that's Milestone 2.2)
- Conversation search (that's FR-5.8, Phase 4)
- Encrypted storage (NFR-2.5, addressed separately)

---

## Current State

### What Exists

- `ChatViewModel` holds `messages: [ChatMessage]` in memory only
- `ContextStore` demonstrates the file-based persistence pattern: JSON encoding, auto-save with Combine debounce, loading on init
- `ChatMessage` is already `Codable` and `Identifiable`

### What's Missing

- No `Conversation` entity wrapping a message list with metadata
- No persistence layer for conversations
- No lifecycle management (create, load, delete)

---

## Proposed Design

### Data Model

#### `Conversation` (new struct)

```swift
struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var modelID: String
    var createdAt: Date
    var updatedAt: Date
    
    init(title: String = "New Conversation", modelID: String = "") {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.modelID = modelID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
```

Place in: `mlx-testing/Conversation.swift`

**Design decisions:**
- `messages` are stored inline (not in separate files) for simplicity. A conversation with 100 messages of ~500 chars each is ~50 KB of JSON — well within reasonable file sizes.
- `modelID` records which model was used, for context when reviewing history.
- `title` is auto-generated from the first user message (first 60 characters) but user-editable later (Milestone 2.2).

#### `ChatMessage` Modifications

No changes required. `ChatMessage` is already `Codable` with all necessary fields (`id`, `role`, `text`, `date`, `toolCallInfo`, `toolResultInfo`).

### ConversationManager

```swift
@MainActor
class ConversationManager: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var activeConversationID: UUID?
    
    var activeConversation: Conversation? {
        get { conversations.first { $0.id == activeConversationID } }
    }
    
    // MARK: - Lifecycle
    
    func createConversation(modelID: String) -> Conversation
    func loadAll() // Load all conversations from disk on init
    func setActive(_ id: UUID)
    
    // MARK: - Persistence
    
    func save(_ conversation: Conversation) // Save single conversation to disk
    func delete(_ id: UUID) // Delete from disk and memory
    
    // MARK: - Auto-save (Combine debounce, same pattern as ContextStore)
    
    private var saveCancellable: AnyCancellable?
    private func setupAutoSave()
}
```

Place in: `mlx-testing/ConversationManager.swift`

**Design decisions:**
- Follows `@MainActor ObservableObject` convention (same as `ContextStore`, `ModelCatalogService`).
- Uses Combine debounce for auto-save (same as `ContextStore`).
- Each conversation is a separate JSON file (easier to manage than one giant file).

### Storage

| Data | Location | Format |
|---|---|---|
| Individual conversations | `~/Library/Application Support/mlx-testing/conversations/{uuid}.json` | JSON `Conversation` |
| Active conversation ID | `UserDefaults` key `"activeConversationID"` | String (UUID) |

**File naming:** Use the conversation UUID as the filename. This avoids filename conflicts and makes lookup trivial.

**Directory structure:**
```
~/Library/Application Support/mlx-testing/
├── contexts.json          (existing)
├── system_prompt.txt      (existing)
├── model_catalog.json     (existing)
├── catalog_metadata.json  (existing)
└── conversations/
    ├── 550e8400-e29b-41d4-a716-446655440000.json
    ├── 6ba7b810-9dad-11d1-80b4-00c04fd430c8.json
    └── ...
```

### Integration with ChatViewModel

```swift
// ChatViewModel changes:

class ChatViewModel: ObservableObject {
    // New: reference to conversation manager
    let conversationManager: ConversationManager
    
    // Existing: messages now backed by active conversation
    var messages: [ChatMessage] {
        get { conversationManager.activeConversation?.messages ?? [] }
        set {
            guard var conv = conversationManager.activeConversation else { return }
            conv.messages = newValue
            conv.updatedAt = Date()
            conversationManager.save(conv)
        }
    }
    
    func send(_ text: String) async {
        // If no active conversation, create one
        if conversationManager.activeConversation == nil {
            let conv = conversationManager.createConversation(
                modelID: selectedModelID
            )
            conversationManager.setActive(conv.id)
        }
        
        // Auto-title from first user message
        if var conv = conversationManager.activeConversation,
           conv.title == "New Conversation" {
            conv.title = String(text.prefix(60))
            conversationManager.save(conv)
        }
        
        // ... existing send logic
    }
}
```

**Key principle:** `ChatViewModel` delegates persistence to `ConversationManager` but retains control of the agentic loop, streaming, and UI state. The `messages` property becomes a computed bridge.

### UI Changes (Minimal for 2.1)

For Milestone 2.1, the UI changes are intentionally minimal:

1. **On launch:** Load the most recent conversation and display its messages
2. **Status bar:** Show conversation title (or "New Conversation")
3. **New conversation:** Add a toolbar button (⌘N) to start a fresh conversation

The full sidebar conversation list, rename, delete, and search are deferred to Milestone 2.2.

---

## Implementation Plan

1. **Create `Conversation` struct** in `mlx-testing/Conversation.swift`
2. **Create `ConversationManager`** in `mlx-testing/ConversationManager.swift`
   - File I/O: load all, save individual, delete
   - Auto-save with Combine debounce
   - Active conversation tracking
3. **Update `ChatViewModel`**
   - Accept `ConversationManager` dependency
   - Bridge `messages` to active conversation
   - Auto-create conversation on first message
   - Auto-title from first user message
4. **Update `ContentView`**
   - Create `ConversationManager` as `@StateObject`
   - Pass to `ChatViewModel`
   - Add "New Conversation" toolbar button
5. **Update README** project structure table
6. **Verify:** Close and reopen app → conversation is restored

---

## Testing Strategy

Since there are no unit tests currently, verification is manual:

- [ ] Send 5 messages → quit app → reopen → all 5 messages visible
- [ ] Tool calls and results are preserved correctly
- [ ] Starting a new conversation clears the chat and creates a new file
- [ ] Deleting `conversations/` directory → app starts cleanly with empty state
- [ ] 50+ conversations load in < 1 second (create test data manually)
- [ ] Conversation JSON files are human-readable and correctly formatted

---

## Open Questions

1. **Should `messages` remain a flat `@Published` array on ChatViewModel, or should views observe `ConversationManager` directly?** 
   - Recommendation: Keep the existing `@Published var messages` pattern on ChatViewModel for backward compatibility. The VM syncs to/from ConversationManager internally.

2. **Maximum conversation size before splitting files?**
   - Recommendation: No splitting for now. A 500-message conversation is ~250 KB JSON — acceptable. Revisit if conversations regularly exceed 1,000 messages.

3. **Migration from ephemeral state?**
   - Recommendation: On first launch with the new code, if there are messages in memory but no conversations directory, save them as the first conversation.

---

*Related: [Requirements FR-5.4](../vision/02-requirements.md) · [Roadmap Milestone 2.1](../vision/06-roadmap.md)*
