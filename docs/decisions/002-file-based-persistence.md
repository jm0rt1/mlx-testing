# ADR-002: File-Based Persistence over Core Data

**Status:** Accepted
**Date:** 2025-01

---

## Context

MLX Copilot needs to persist several types of data across app sessions:
- Context bubbles (skills, instructions, memories)
- Base system prompt
- Model catalog
- Conversation history (planned)
- Vector indices for RAG (planned)

We need a persistence strategy that is simple, inspectable, and reliable.

## Decision

We chose **file-based persistence using JSON files and plain text** stored in `~/Library/Application Support/mlx-testing/`. Simple user preferences use `UserDefaults`.

## Rationale

1. **Human-readable.** JSON files can be opened in any text editor, inspected, and manually edited. This is invaluable during development and debugging. Users who want to back up, migrate, or inspect their data can do so trivially.

2. **No schema migrations.** Core Data and SQLite require migration strategies when the schema changes. JSON files with `Codable` structs handle evolution naturally — new fields get default values, removed fields are ignored by the decoder.

3. **Simple implementation.** The persistence layer is ~50 lines of code per store (see `ContextStore`). No Core Data stack, no `NSManagedObjectContext`, no fetch requests, no thread safety concerns beyond `@MainActor`.

4. **Appropriate scale.** Our data volumes are small:
   - Context bubbles: ~10 KB (dozens of entries)
   - Conversations: ~50–500 KB each (hundreds of messages)
   - Model catalog: ~200 KB (hundreds of entries)
   
   File-based storage handles these sizes easily. We're not building a database-scale application.

5. **Portability.** Users can copy their `~/Library/Application Support/mlx-testing/` directory to another Mac and have all their data. No database export/import needed.

6. **Testability.** Tests can create a temporary directory, write test fixtures as JSON, and verify outputs — no database setup or teardown.

## Alternatives Considered

### Core Data

- **Pros:** Built-in to Apple platforms, handles relationships, migration tooling, iCloud sync
- **Cons:** Heavy setup (model editor, stack configuration, contexts). Threading model is complex. Overkill for our data volume. Not human-readable. Migration is a solved but non-trivial problem.
- **Why rejected:** The complexity overhead is not justified by our scale. We don't need relationships, queries, or iCloud sync.

### SQLite (direct or via GRDB/SQLite.swift)

- **Pros:** Fast queries, mature, lightweight
- **Cons:** Adds a dependency (unless using raw C API). Not human-readable. Requires schema management. Overkill for key-value-like access patterns.
- **Why rejected:** We primarily read/write entire documents (all context bubbles, entire conversations). We don't need SQL queries or joins.

### SwiftData

- **Pros:** Modern Apple framework, Swift-native, simpler than Core Data
- **Cons:** Requires macOS 14+, relatively new (limited community experience), still has Core Data's complexity model at heart.
- **Why rejected:** Too new with insufficient track record. File-based approach is simpler and more portable.

### Realm

- **Pros:** Fast, reactive, cross-platform
- **Cons:** External dependency (violates our "minimal dependencies" principle). Heavy runtime. Overkill.
- **Why rejected:** Violates ADR principle of minimal external dependencies.

## Consequences

### Positive
- Extremely simple to implement and understand
- Human-readable data files aid debugging and user trust
- No migration complexity — `Codable` handles schema evolution
- Easy backup and portability
- Zero external dependencies for persistence

### Negative
- **No querying.** Finding a specific conversation by content requires loading all conversations. Acceptable at our scale (< 1,000 conversations).
- **No relationships.** Cross-entity references use UUID lookups, not foreign keys. Acceptable for our simple data model.
- **Concurrent access.** If we ever need multi-process access (e.g., main app + menu bar agent), we'll need file coordination. Mitigated by `@MainActor` isolation within a single process.
- **Scale ceiling.** If conversation count exceeds ~10,000 or vector indices exceed ~100 MB, we may need to reconsider. This is far beyond current projections.

### Revisit Triggers

Consider revisiting this decision if:
- Conversation search becomes a core feature requiring full-text indexing
- Multi-process access is needed (main app + menu bar helper)
- Data volume exceeds 100 MB in the Application Support directory
- Users request iCloud sync

---

*Related: [Domain Model — Persistence](../vision/03-domain-model.md) · [Architecture](../vision/05-architecture.md)*
