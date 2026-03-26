# ADR-003: Protocol-Oriented Service Architecture

**Status:** Accepted
**Date:** 2025-01

---

## Context

MLX Copilot uses an LLM inference engine that may change backends (MLX real model vs. stub for development), and will add new inference types (vision models, embedding models). We need an architecture that supports:
- Swapping implementations at runtime (MLX ↔ Stub)
- Adding new backend types (cloud API, different frameworks)
- Testing without real model inference
- Consistent interfaces across different model types

## Decision

We adopted a **protocol-oriented service architecture** where every major subsystem is accessed through a Swift protocol. View models interact only with protocols, never with concrete implementations.

## Rationale

1. **Runtime backend switching.** The `LLMService` protocol lets us swap between `LocalLLMServiceMLX` (real inference) and `LocalLLMServiceStub` (simulated streaming) at runtime via a toolbar picker. The view model doesn't know or care which implementation is active.

2. **Future extensibility.** The same pattern extends naturally to:
   - `VLMService` → `LocalVLMServiceMLX` (Milestone 3.1)
   - `EmbeddingService` → `LocalEmbeddingServiceMLX` (Milestone 3.3)
   - `CloudLLMService` for optional cloud backends (if ever added)
   
   Each new capability gets a protocol first, then one or more implementations.

3. **Testability.** Stub implementations serve as test doubles. When unit tests are added, they can use stubs to test view model logic without loading a real model (which requires GPU and takes seconds).

4. **Dependency protection.** The `ChatViewModel` depends on `LLMService`, not on `MLX`, `MLXLLM`, or any specific framework type. If MLX Swift introduces breaking changes, only the concrete implementation needs updating — the view model and UI are unaffected.

5. **Swift alignment.** Protocol-oriented programming is a core Swift paradigm. This architecture feels natural to Swift developers and leverages features like protocol extensions, associated types, and existential types.

## Implementation Pattern

### Service Protocol

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

### Concrete Implementations

```swift
class LocalLLMServiceMLX: LLMService { /* MLX framework calls */ }
class LocalLLMServiceStub: LLMService { /* Simulated streaming */ }
```

### View Model (protocol-only dependency)

```swift
@MainActor
class ChatViewModel: ObservableObject {
    private var llmService: LLMService  // Protocol, not concrete type
    
    func switchBackend(_ backend: LLMBackend) {
        llmService = backend == .mlx
            ? LocalLLMServiceMLX(modelID: selectedModelID)
            : LocalLLMServiceStub()
    }
}
```

### Tool Protocol

The same pattern applies to the agent tool system:

```swift
protocol AgentTool {
    var name: String { get }
    var toolDescription: String { get }
    var parameters: [ToolParameter] { get }
    var requiresApproval: Bool { get }
    var riskLevel: ToolRiskLevel { get }
    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult
}
```

New tools implement this protocol and register in `ToolRegistry`. The executor works with `AgentTool` references, never concrete types.

## Alternatives Considered

### Concrete class hierarchy (inheritance)

- **Pros:** Shared implementation via base class
- **Cons:** Swift favors composition over inheritance. Base classes create tight coupling. Multiple inheritance isn't supported in Swift.
- **Why rejected:** Protocols with default implementations (via extensions) achieve the same code sharing without inheritance coupling.

### Enum-based switching with direct framework calls

- **Pros:** Simpler for two backends
- **Cons:** Doesn't scale. Adding a third backend means editing every switch statement. View model becomes coupled to all frameworks.
- **Why rejected:** Protocol-oriented approach scales naturally and keeps dependencies isolated.

### Dependency injection container

- **Pros:** Formal DI (like Swinject)
- **Cons:** Adds an external dependency. Overkill for our scale. Swift's native protocol conformance and init-based injection are sufficient.
- **Why rejected:** Simple init injection (passing the service to the view model) is adequate. No need for a DI framework.

## Consequences

### Positive
- Clean separation between interface and implementation
- Runtime backend switching with zero view model changes
- Natural extension path for VLM, embeddings, and cloud services
- Stub implementations enable fast UI development
- Framework changes are isolated to concrete implementations

### Negative
- **Protocol overhead.** Each new capability requires defining a protocol first, even if there's initially only one implementation. This is a small cost for the flexibility gained.
- **Existential performance.** Protocol existentials have a slight runtime cost compared to concrete types. Irrelevant for our use case (the bottleneck is model inference, not method dispatch).
- **More files.** Each service area involves a protocol file and one or more implementation files. Acceptable given the project's flat file structure.

---

*Related: [ADR-001: MLX Swift](001-mlx-swift-for-inference.md) · [Architecture](../vision/05-architecture.md)*
