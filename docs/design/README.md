# Technical Design Documents

Technical design documents (TDDs) provide implementation-level specifications for upcoming milestones. Each document bridges the gap between the high-level [vision](../vision/) and actual code.

---

## Active Design Documents

| Document | Milestone | Status |
|---|---|---|
| [Conversation Persistence](phase2-conversation-persistence.md) | 2.1 | Ready for implementation |
| [Generation Metrics](phase2-generation-metrics.md) | 2.3 | Ready for implementation |
| [Generation Parameters](phase2-generation-parameters.md) | 2.4 | Ready for implementation |

---

## Design Document Template

When creating a new TDD, use this structure:

```markdown
# Title — [Milestone ID]

## Overview
Brief description of what this document covers and which milestone it supports.

## Goals
What this design aims to achieve.

## Non-Goals
What is explicitly out of scope for this design.

## Current State
How things work today (relevant context).

## Proposed Design

### Data Model
New or modified structs, protocols, and types.

### API Surface
New public methods and properties on existing types.

### Storage
Persistence approach and file/key locations.

### UI Changes
New views or modifications to existing views.

## Implementation Plan
Ordered list of incremental steps to implement this design.

## Testing Strategy
How to verify the implementation works correctly.

## Open Questions
Unresolved design decisions (address before implementation begins).
```

---

## How to Use These Documents

1. **Before starting a milestone** — Read the relevant TDD to understand the planned approach
2. **During implementation** — Use the TDD as a reference for data models, API surfaces, and UI changes
3. **After implementation** — Update the TDD status and note any deviations from the original design
4. **When planning a new milestone** — Create a TDD using the template above before writing code
