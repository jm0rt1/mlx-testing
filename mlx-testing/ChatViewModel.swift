import Combine
import Foundation
import SwiftUI

/// Which LLM back-end to use.
enum LLMBackend: String, CaseIterable, Identifiable {
    case mlx  = "MLX (real model)"
    case stub = "Stub (simulated)"
    var id: String { rawValue }
}

@MainActor
final class ChatViewModel: ObservableObject {

    // ── Published state ────────────────────────────────────────────────
    @Published private(set) var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var status: String = "Idle"
    @Published private(set) var downloadProgress: Double = 0.0
    @Published private(set) var isDownloading: Bool = false

    /// Toggle between MLX and stub back-ends.
    @Published var backend: LLMBackend {
        didSet { switchService() }
    }

    // ── Context store (shared with UI) ─────────────────────────────────
    let contextStore = ContextStore()

    // ── Private state ──────────────────────────────────────────────────
    private var llmService: LLMService
    private var generationTask: Task<Void, Never>?

    // ── Init ───────────────────────────────────────────────────────────

    init(backend: LLMBackend = .mlx) {
        self.backend = backend
        self.llmService = backend == .mlx ? LocalLLMServiceMLX() : LocalLLMServiceStub()
    }

    // ── Switch back-end ────────────────────────────────────────────────

    private func switchService() {
        cancelGeneration()
        llmService = backend == .mlx ? LocalLLMServiceMLX() : LocalLLMServiceStub()
        messages = []
        status = "Switched to \(backend.rawValue)"
        isLoading = false
        downloadProgress = 0
        isDownloading = false
    }

    // ── Model loading ──────────────────────────────────────────────────

    func loadModelIfNeeded() async {
        guard !llmService.isLoaded else {
            status = llmService.statusMessage
            return
        }
        do {
            isDownloading = true
            status = "Loading model…"

            let progressTask = Task {
                while !llmService.isLoaded {
                    try await Task.sleep(nanoseconds: 100 * 1_000_000)
                    downloadProgress = llmService.downloadProgress
                    status = llmService.statusMessage
                }
            }

            try await llmService.load()

            progressTask.cancel()
            downloadProgress = 1.0
            isDownloading = false
            status = llmService.statusMessage
        } catch {
            isDownloading = false
            status = "Failed to load: \(error.localizedDescription)"
        }
    }

    // ── Send message ───────────────────────────────────────────────────

    func send() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        input = ""
        isLoading = true
        status = "Generating…"

        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))

        // Build the composed system prompt from the context store
        let composedPrompt = contextStore.composedSystemPrompt

        do {
            try await llmService.generateReplyStreaming(
                from: messages,
                systemPrompt: composedPrompt
            ) { [weak self] token in
                guard let self else { return }
                if let idx = self.messages.lastIndex(where: { $0.id == assistantID }) {
                    self.messages[idx].text += token
                }
            }
            status = "Done"
        } catch is CancellationError {
            status = "Cancelled"
        } catch {
            if let idx = messages.lastIndex(where: { $0.id == assistantID }) {
                messages[idx].text = "⚠️ \(error.localizedDescription)"
            }
            status = "Generation failed"
        }

        isLoading = false
    }

    // ── Cancel generation ──────────────────────────────────────────────

    func cancelGeneration() {
        llmService.cancelGeneration()
        isLoading = false
        status = "Cancelled"
    }

    // ── Clear conversation ─────────────────────────────────────────────

    func clearConversation() {
        cancelGeneration()
        messages = []
        status = llmService.isLoaded ? "Model loaded" : "Idle"
    }
}
