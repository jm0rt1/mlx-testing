# Documentation — MLX Copilot

> Comprehensive documentation for the MLX Copilot project: a privacy-first, on-device AI companion for macOS.

---

## Document Map

| Section | Purpose | Audience |
|---|---|---|
| [Vision](vision/) | Product vision, requirements, architecture, and roadmap | Everyone |
| [Design](design/) | Technical design documents for upcoming milestones | Developers |
| [Guides](guides/) | How-to guides for development and contribution | Contributors |
| [Decisions](decisions/) | Architectural Decision Records (ADRs) | Developers, reviewers |

---

## Quick Links

### Vision & Strategy

- [Concept](vision/01-concept.md) — What we're building and why
- [Requirements](vision/02-requirements.md) — Functional & non-functional requirements
- [Domain Model](vision/03-domain-model.md) — Core entities and data flows
- [Features & Use Cases](vision/04-features-and-use-cases.md) — Feature catalog and user stories
- [Architecture](vision/05-architecture.md) — Target architecture and module boundaries
- [Roadmap](vision/06-roadmap.md) — Phased delivery plan with milestones

### Technical Design (Phase 2)

- [Conversation Persistence](design/phase2-conversation-persistence.md) — TDD for saving and restoring conversations
- [Generation Metrics](design/phase2-generation-metrics.md) — TDD for tokens-per-second display
- [Generation Parameters](design/phase2-generation-parameters.md) — TDD for temperature, top-p, and max token controls

### Developer Guides

- [Development Setup](guides/development-setup.md) — Environment setup, building, and running
- [Adding Tools](guides/adding-tools.md) — Step-by-step guide to creating new agent tools
- [Contributing](guides/contributing.md) — Contribution workflow, conventions, and PR process

### Architectural Decisions

- [ADR-001: MLX Swift for Inference](decisions/001-mlx-swift-for-inference.md) — Why we chose MLX Swift
- [ADR-002: File-Based Persistence](decisions/002-file-based-persistence.md) — Why JSON files over Core Data
- [ADR-003: Protocol-Oriented Services](decisions/003-protocol-oriented-services.md) — Why protocol-driven architecture

---

## How Documentation is Organized

```
docs/
├── README.md                    ← You are here
├── vision/                      # Product vision and strategy
│   ├── 01-concept.md
│   ├── 02-requirements.md
│   ├── 03-domain-model.md
│   ├── 04-features-and-use-cases.md
│   ├── 05-architecture.md
│   └── 06-roadmap.md
├── design/                      # Technical design documents
│   ├── phase2-conversation-persistence.md
│   ├── phase2-generation-metrics.md
│   └── phase2-generation-parameters.md
├── guides/                      # Developer and contributor guides
│   ├── development-setup.md
│   ├── adding-tools.md
│   └── contributing.md
└── decisions/                   # Architectural Decision Records
    ├── 001-mlx-swift-for-inference.md
    ├── 002-file-based-persistence.md
    └── 003-protocol-oriented-services.md
```

### When to Add Documentation

| Situation | Action |
|---|---|
| New milestone or feature planned | Add a technical design doc in `design/` |
| Significant architectural choice | Add an ADR in `decisions/` |
| New development workflow or tool | Add or update a guide in `guides/` |
| Product direction change | Update the relevant vision doc |
| New Swift file added | Update the README project structure table |

---

## Conventions

- All docs use **Markdown** with GitHub-Flavored Markdown (GFM) extensions
- Tables use `|---|---|` alignment rows
- Code blocks use triple backticks with language tags (`swift`, `bash`, `json`)
- Keyboard shortcuts use symbols: `⌘`, `⌥`, `⇧`
- Bullet lists use `-` (not `*`)
- Section separators use `---`
- Each document includes navigation links to previous/next documents where applicable
