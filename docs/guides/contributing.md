# Contributing Guide

> How to contribute to MLX Copilot: workflow, conventions, and quality expectations.

---

## Contribution Workflow

### 1. Pick a Task

- Check the [Roadmap](../vision/06-roadmap.md) for planned milestones
- Check [open issues](https://github.com/jm0rt1/mlx-testing/issues) for bugs or feature requests
- Review [technical design documents](../design/) for implementation-ready specifications

### 2. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-fix-description
```

**Branch naming:**
- `feature/` — new functionality
- `fix/` — bug fix
- `docs/` — documentation only
- `refactor/` — code restructuring with no behavior change

### 3. Make Changes

Follow the conventions below. Keep changes focused — one feature or fix per PR.

### 4. Test Manually

Since there are no automated tests yet, verify your changes manually:
- Build succeeds (⌘B)
- App launches and core features work (⌘R)
- Your specific feature/fix works as expected
- No regressions in related areas

### 5. Submit a Pull Request

Use the [PR template](../../.github/pull_request_template.md) and complete all checklist items.

---

## Code Conventions

### Swift Style

| Convention | Rule |
|---|---|
| Naming | Swift API Design Guidelines: camelCase for properties/methods, PascalCase for types |
| Comments | Concise `//` or `///` doc comments. `// MARK: -` for section headers |
| Force unwraps | Prohibited in new code (except well-known safe cases) |
| Concurrency | `async/await` and `Task`. No Dispatch queues or completion handlers |
| Combine | Only for auto-save debouncing. Prefer async/await elsewhere |
| Error handling | `do/catch` or `throws`. No `try!` in new code |

### Architecture Rules

| Rule | Details |
|---|---|
| `@MainActor` | Required on all `ObservableObject` classes |
| Protocol-first | New services should define a protocol before the implementation |
| Value types for data | Data models are structs (`Identifiable`, `Codable`, `Hashable`) |
| Flat file structure | Source files go in `mlx-testing/` (tools in `mlx-testing/AgentTools/`) |
| No new dependencies | Only MLX Swift ecosystem packages. Discuss before adding others |

### SwiftUI Patterns

| Pattern | Details |
|---|---|
| `@StateObject` | Only at creation site (e.g., `ContentView` for `ChatViewModel`) |
| `@ObservedObject` | When receiving an existing observable |
| `@Binding` | For simple two-way data flow to sub-views |
| Private sub-views | Declare as `private struct` in the same file as the parent |
| NavigationSplitView | Used for sidebar/detail layout. Do not switch to NavigationStack |

---

## File Placement

| File type | Location |
|---|---|
| Swift source files | `mlx-testing/` |
| Agent tools | `mlx-testing/AgentTools/` |
| Documentation | `docs/` |
| Vision docs | `docs/vision/` |
| Technical designs | `docs/design/` |
| Developer guides | `docs/guides/` |
| Decision records | `docs/decisions/` |
| Agent instructions | `.github/agents/` |
| Copilot instructions | `.github/copilot-instructions.md` |

---

## Documentation Updates

When your PR includes:

| Change | Update required |
|---|---|
| New Swift file | README project structure tree |
| New feature | README features list |
| New dependency | README package dependencies table |
| New entitlement | README entitlements table + `.github/copilot-instructions.md` |
| New tool | README project structure + features list |
| Architecture change | `.github/copilot-instructions.md` |
| New milestone design | `docs/design/` — add a TDD |
| Significant design decision | `docs/decisions/` — add an ADR |

---

## PR Checklist

Every PR should address these items (from the [PR template](../../.github/pull_request_template.md)):

- [ ] New Swift files are placed in `mlx-testing/` (or `mlx-testing/AgentTools/` for tools)
- [ ] `@MainActor` is applied to any new `ObservableObject` class
- [ ] New `AgentTool` implementations are registered in `ToolRegistry.registerDefaults()`
- [ ] Entitlements plist is updated if new sandbox permissions are needed
- [ ] README project structure table is updated for any new files
- [ ] Data models remain `Codable` and `Hashable`
- [ ] All async work supports cancellation via `Task.checkCancellation()`
- [ ] Large tool outputs are truncated with a character limit
- [ ] No hardcoded model IDs outside `ModelCatalogService.defaultModelID`
- [ ] Copilot instructions updated if architecture changed

---

## Commit Messages

Use clear, imperative-mood commit messages:

```
Add conversation persistence with auto-save
Fix model picker search not filtering correctly
Update README with new project structure
Refactor ContextStore to use async file I/O
```

For multi-line commits:
```
Add generation metrics display

- Add GenerationMetrics struct to ChatMessage
- Instrument token counting in ChatViewModel
- Show live tok/s in status bar during generation
- Display metrics footer on completed assistant messages
```

---

## Getting Help

- Review the [Architecture documentation](../vision/05-architecture.md) for system design context
- Read the [Copilot Instructions](../../.github/copilot-instructions.md) for detailed coding conventions
- Check [Architectural Decision Records](../decisions/) for rationale behind key choices
- Check [Technical Design Documents](../design/) for implementation specifications

---

*Related: [Development Setup](development-setup.md) · [Adding Tools](adding-tools.md)*
