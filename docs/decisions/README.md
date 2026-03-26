# Architectural Decision Records

Architectural Decision Records (ADRs) capture significant design decisions, their context, and their rationale. They help future contributors understand *why* things are the way they are.

---

## Index

| ADR | Title | Status | Date |
|---|---|---|---|
| [001](001-mlx-swift-for-inference.md) | MLX Swift for Local Inference | Accepted | 2025-01 |
| [002](002-file-based-persistence.md) | File-Based Persistence over Core Data | Accepted | 2025-01 |
| [003](003-protocol-oriented-services.md) | Protocol-Oriented Service Architecture | Accepted | 2025-01 |

---

## ADR Template

When recording a new decision, use this structure:

```markdown
# ADR-NNN: Title

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-XXX
**Date:** YYYY-MM

## Context
What situation or problem led to this decision?

## Decision
What did we decide?

## Rationale
Why did we choose this option over the alternatives?

## Alternatives Considered
What other options were evaluated?

## Consequences
What are the positive and negative outcomes of this decision?
```

---

## When to Write an ADR

Write an ADR when you:
- Choose a framework, library, or significant dependency
- Establish a pattern that the whole codebase should follow
- Decide between two or more reasonable approaches and pick one
- Change a previous architectural decision (supersede the old ADR)
- Make a decision that future contributors might question
