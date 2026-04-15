# EdgeClaw MVP Plan (starting from `mlx-testing`)

This is the concrete path for turning the existing Swift prototype into the first commercial EdgeClaw app.

## Why this repo is the right starting point
The prototype already has the hard parts we need:
- native macOS SwiftUI chat UI
- local MLX inference
- model picker
- streaming output
- context system
- tool approval system
- persistent app support storage

That means we do **not** need to invent the app shell. We need to narrow and productize it.

## Product direction
Turn `mlx-testing` into **EdgeClaw**, a lightweight local agent app for small models, especially `gemma-4-e4b`.

## What to change first

### 1. Rename + reposition the app
Files touched:
- `mlx-testing/mlx_testingApp.swift`
- Xcode target/app metadata
- README / docs

Change:
- rename visible app/product strings from prototype naming to `EdgeClaw`
- update the app subtitle/marketing copy toward small-model local agent use

### 2. Change the default model and default behavior
Files touched:
- `mlx-testing/ModelCatalogService.swift`
- `mlx-testing/ChatViewModel.swift`
- `mlx-testing/LocalLLMService.swift`

Change:
- default model -> `gemma-4-e4b`
- lower default `maxTokens`
- lower/default deterministic temperature
- keep the app biased toward low-overhead operation

### 3. Replace generic context bubbles with a more opinionated Lite workflow
Files touched:
- `mlx-testing/ContextStore.swift`
- `mlx-testing/ContextBubble.swift`
- `mlx-testing/ContextBubbleEditor.swift`
- `mlx-testing/SystemPromptEditor.swift`

Change:
- keep context system, but bias it toward:
  - taskboard
  - instructions
  - memory
- reduce arbitrary prompt sprawl
- ship a tighter default system prompt

### 4. Add a durable taskboard as a first-class concept
New files likely:
- `mlx-testing/TaskBoard.swift`
- `mlx-testing/TaskBoardStore.swift`
- `mlx-testing/TaskBoardView.swift`

Integration points:
- `ChatViewModel.swift`
- sidebar UI in `ContentView.swift`

Goal:
- store one active goal
- store next action
- make the assistant resume work instead of drifting

This is one of the strongest differentiators versus a generic local chat wrapper.

### 5. Tighten tool defaults for commercial safety
Files touched:
- `mlx-testing/AgentTools/ToolRegistry.swift`
- `mlx-testing/ToolPickerView.swift`
- possibly approval UI files

Change:
- default fewer tools on
- ship a safer preset
- let advanced users opt into shell/file system power gradually

### 6. Add product settings for Lite mode
New or extended settings:
- low-overhead preset
- tool preset
- heartbeat/taskboard behavior
- model profile selection

## First shipping scope
Version 1 should be:
- chat UI
- local MLX inference
- Gemma-first defaults
- durable taskboard
- smaller/safer tool surface
- polished onboarding and settings

## What not to build in v1
- full OpenClaw parity
- huge plugin system
- multimodal complexity
- broad OS-wide automation surface
- hosted sync/cloud accounts

## Best first coding sequence
1. change model defaults
2. tighten prompt/context defaults
3. add taskboard persistence layer
4. add taskboard UI in sidebar
5. wire taskboard into prompt composition
6. reduce default tool surface
7. polish onboarding/copy

## Immediate next code targets
- inspect `ModelCatalogService.swift`
- inspect `LocalLLMService.swift`
- inspect `ContentView.swift`
- inspect `ContextBubbleEditor.swift`
- design `TaskBoardStore.swift`

## Commercial framing
The product is not “a local chat app.”
It is:

> a lightweight local agent app that actually works on small models

That is a much better product story.
