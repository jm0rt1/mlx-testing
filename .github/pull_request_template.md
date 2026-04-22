## Summary

<!-- Brief description of what this PR does. -->

## Changes

<!-- List the key changes made in this PR. -->

-

## Checklist

- [ ] New Swift files are placed in `mlx-testing/` (or `mlx-testing/AgentTools/` for tools)
- [ ] `@MainActor` is applied to any new `ObservableObject` class
- [ ] New `AgentTool` implementations are registered in `ToolRegistry.registerDefaults()`
- [ ] Entitlements plist is updated if new sandbox permissions are needed
- [ ] README project structure table is updated for any new files
- [ ] Data models remain `Codable` and `Hashable`
- [ ] All async work supports cancellation via `Task.checkCancellation()`
- [ ] Large tool outputs are truncated with a character limit
- [ ] No hardcoded model IDs outside `ModelCatalogService.defaultModelID`
- [ ] Copilot instructions (`.github/copilot-instructions.md`) are updated if architecture changed
