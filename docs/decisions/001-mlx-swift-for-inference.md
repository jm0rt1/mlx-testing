# ADR-001: MLX Swift for Local Inference

**Status:** Accepted
**Date:** 2025-01

---

## Context

MLX Copilot needs to run large language models locally on macOS without any cloud dependency. The core requirement is: all inference happens on-device, on Apple Silicon, with no data leaving the user's machine.

Several options exist for local inference on macOS:
- **MLX Swift** — Apple's array framework for machine learning on Apple Silicon, with native Swift bindings
- **llama.cpp** — C++ inference engine with Metal support and Swift-compatible C API
- **Core ML** — Apple's built-in ML framework for deploying trained models
- **ONNX Runtime** — Cross-platform ML inference with Metal execution provider

## Decision

We chose **MLX Swift** (`mlx-swift` + `mlx-swift-lm`) as the sole inference backend.

## Rationale

1. **Native Swift API.** MLX Swift provides first-class Swift bindings. No C interop, no bridging headers, no Objective-C++ wrappers. This aligns with our all-Swift codebase and simplifies the build.

2. **Unified memory optimization.** MLX is designed from the ground up for Apple Silicon's unified memory architecture. It uses Metal GPU acceleration automatically, with lazy evaluation and minimal memory copies. This is critical for running 4B–30B parameter models on consumer Macs.

3. **Active MLX ecosystem.** The `mlx-swift-lm` library provides:
   - `MLXLLM` — text language model loading and generation
   - `MLXVLM` — vision-language model support (future Milestone 3.1)
   - `MLXEmbedders` — embedding model support (future Milestone 3.3)
   - `MLXLMCommon` — shared infrastructure for model loading and tokenization
   
   This gives us a single dependency ecosystem for text, vision, and embedding models.

4. **HuggingFace Hub integration.** MLX Swift LM can download and load models directly from HuggingFace Hub using model repo IDs. The `mlx-community` organization on HuggingFace provides a growing catalog of pre-quantized models in MLX format.

5. **Apple backing.** MLX is developed by Apple's machine learning research team. It is actively maintained and aligned with Apple Silicon hardware evolution.

## Alternatives Considered

### llama.cpp

- **Pros:** Broader model support, battle-tested, very fast inference, large community
- **Cons:** C++ codebase requires bridging to Swift. No native Swift API. Model format (GGUF) is different from HuggingFace ecosystem. Would need a separate solution for vision and embedding models.
- **Why rejected:** The C/Swift interop adds complexity, and we'd need to maintain model format conversions. MLX's unified ecosystem (text + vision + embeddings) is a significant advantage.

### Core ML

- **Pros:** Built into macOS, Apple-supported, Neural Engine access
- **Cons:** Requires model conversion to Core ML format (`.mlmodelc`). Limited support for generative LLMs. No streaming token generation API. Model conversion is fragile and model-specific.
- **Why rejected:** Core ML is optimized for classification and small models, not for generative LLM inference with streaming. The conversion pipeline is brittle.

### ONNX Runtime

- **Pros:** Cross-platform, wide model support
- **Cons:** Not optimized for Apple Silicon unified memory. Metal support is secondary. No Swift-native API.
- **Why rejected:** Performance on Apple Silicon is inferior to MLX, and the cross-platform benefits are irrelevant for a macOS-only app.

## Consequences

### Positive
- Clean, all-Swift codebase with no foreign language interop
- Excellent Apple Silicon performance with minimal configuration
- Single dependency ecosystem covers text, vision, and embedding models
- Direct HuggingFace Hub integration for model discovery and download

### Negative
- **Apple Silicon only.** Intel Macs are not supported. This is acceptable given our target audience.
- **Younger ecosystem.** MLX Swift is newer than llama.cpp. Some models may not be available in MLX format yet.
- **API stability.** MLX Swift is pre-1.0 and may introduce breaking changes. Mitigated by pinning dependency versions and abstracting behind protocols ([ADR-003](003-protocol-oriented-services.md)).

---

*Related: [ADR-003: Protocol-Oriented Services](003-protocol-oriented-services.md) · [Architecture](../vision/05-architecture.md)*
