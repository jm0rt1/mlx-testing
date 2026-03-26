# Vision — MLX Copilot

> A privacy-first, on-device AI operating system companion for macOS,
> powered by Apple Silicon and MLX.

---

## Document Index

| # | Document | Purpose |
|---|---|---|
| 1 | [Concept](VISION-01-concept.md) | High-level vision, guiding principles, and value proposition |
| 2 | [Requirements](VISION-02-requirements.md) | Functional requirements, non-functional requirements, and constraints |
| 3 | [Domain Model](VISION-03-domain-model.md) | Core entities, relationships, and data flows |
| 4 | [Features & Use Cases](VISION-04-features-and-use-cases.md) | Feature catalog, user stories, and use case narratives |
| 5 | [Architecture](VISION-05-architecture.md) | Target architecture, module boundaries, and integration patterns |
| 6 | [Roadmap](VISION-06-roadmap.md) | Phased delivery plan with milestones and success criteria |

---

## How to Read These Documents

These documents describe a **forward-looking vision** for where the mlx-testing application is heading. They are organized following standard systems engineering practices:

1. **Concept** — Start here. Understand *what* we are building and *why*.
2. **Requirements** — The measurable constraints and capabilities the system must satisfy.
3. **Domain Model** — The shared vocabulary and structural foundation for the system.
4. **Features & Use Cases** — Concrete scenarios that bring the requirements to life.
5. **Architecture** — How the system is structured to deliver the features.
6. **Roadmap** — When and in what order we deliver.

Each document is self-contained but cross-references the others where appropriate.

---

## Current State

The application today is a native macOS SwiftUI chat interface that:

- Runs quantized LLMs **entirely on-device** via MLX Swift on Apple Silicon
- Streams token output in real time with cancellation support
- Dynamically discovers and manages models from the Hugging Face Hub
- Composes system prompts from toggleable context bubbles (skills, instructions, memories)
- Exposes an agentic tool-calling system (file system, shell, clipboard, app launcher)
- Persists context and settings to disk

The vision documents describe the evolution from this foundation into something significantly more capable.
