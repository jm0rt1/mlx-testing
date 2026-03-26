# 1 — Concept

## Vision Statement

**MLX Copilot** is a privacy-first, on-device AI operating system companion for macOS. It combines large language models, vision models, embeddings, and agentic tool use — all running locally on Apple Silicon — to become a persistent, intelligent partner that understands your work, sees your screen, searches your files, and acts on your behalf, without any data ever leaving your machine.

---

## The Problem

Today's AI assistants fall into two camps:

1. **Cloud-hosted copilots** (ChatGPT, Claude, Gemini) — powerful, but every keystroke, screenshot, and document is sent to a remote server. Users trade privacy for capability.
2. **Local chat wrappers** — private, but limited to simple question-and-answer exchanges with no awareness of the user's actual environment.

Neither camp delivers what power users actually want: **an AI that lives inside their operating system, understands their context, and can take action — all without phoning home.**

---

## The Opportunity

Apple Silicon's unified memory architecture makes it uniquely possible to run capable LLMs (4B–30B parameters), vision-language models, and embedding models simultaneously on a consumer laptop. The MLX ecosystem provides the native Swift framework to do this efficiently. macOS provides rich APIs for accessibility, file system access, automation, and inter-process communication.

By combining these three pillars — **local AI inference**, **OS-level integration**, and **persistent personal context** — we can build something that cloud services structurally cannot: an AI that is always available, deeply integrated, and unconditionally private.

---

## Guiding Principles

### 1. Privacy is non-negotiable

All inference, storage, and context remain on-device. No telemetry, no cloud sync, no API keys required. The user's data never leaves their Mac.

### 2. Local-first, cloud-optional

The system must be fully functional offline. Cloud model APIs (OpenAI, Anthropic, etc.) may be offered as an optional backend for users who want them, but are never required.

### 3. Agentic by default

The AI is not a passive question-answerer. It observes, reasons, and acts — reading files, running commands, launching applications, and composing multi-step workflows — with the user's informed consent.

### 4. Context is king

The AI maintains a rich, evolving understanding of the user: their projects, preferences, habits, and active work. This context is built up over time through explicit bubbles, conversation history, and automated observation — and is always user-visible and user-editable.

### 5. Progressive trust

New tools and capabilities start gated behind approval prompts. As the user builds confidence, they can grant permanent approval or elevate the agent's autonomy. The system never assumes trust it hasn't earned.

### 6. Native macOS citizen

The application looks, feels, and behaves like a first-class macOS app. It uses SwiftUI, respects system conventions (menu bar, keyboard shortcuts, sandboxing), and integrates with macOS features (Spotlight, Services, Shortcuts, Accessibility).

---

## Value Proposition

| Audience | Value |
|---|---|
| **Software engineers** | A local coding assistant that reads your project, runs your tests, and suggests changes — with zero latency and zero data leakage |
| **Researchers & writers** | A research companion that indexes your documents, searches semantically, and drafts summaries — entirely offline |
| **Privacy-conscious professionals** | A capable AI assistant for sensitive work (legal, medical, financial) where cloud AI is unacceptable |
| **Power users & tinkerers** | A hackable, extensible agent framework where new tools and capabilities can be added in a single Swift file |
| **Apple ecosystem users** | A native macOS app that leverages the full power of Apple Silicon's unified memory and Metal GPU |

---

## Product Name

The working product name is **MLX Copilot** — reflecting its role as an always-available companion that copilots the user's work on macOS, powered by the MLX inference engine.

> The current repository name `mlx-testing` reflects the project's prototype origins and may be updated as the product matures.

---

## What Success Looks Like

A user opens their Mac and MLX Copilot is quietly running. They:

1. **Ask a question** — the AI answers instantly, using a local LLM, with no network required.
2. **Share a screenshot** — the vision model describes the content and can act on it.
3. **Say "find my notes about the MLX architecture"** — the embedding model semantically searches their documents and surfaces the most relevant passages.
4. **Say "refactor this function and run the tests"** — the agent reads the file, makes the edit, executes the test suite, and reports the results.
5. **Leave for the weekend** — when they return, the AI remembers their open projects, pending tasks, and preferred coding style.

All of this happens locally. All of it is private. All of it is fast.

---

*Next: [Requirements →](VISION-02-requirements.md)*
