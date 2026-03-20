import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - LLM Service Protocol

/// Contract used by the view-model for model loading and text generation.
protocol LLMService: AnyObject {
    var isLoaded: Bool { get }
    var downloadProgress: Double { get }
    var statusMessage: String { get }
    func load() async throws
    func generateReplyStreaming(
        from messages: [ChatMessage],
        systemPrompt: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws
    func cancelGeneration()
}

// MARK: - MLX-backed Implementation

/// Real MLX Swift LM service using `ModelContainer` and `ChatSession`.
///
/// **Model caching**: MLX downloads weights to `~/Library/Caches/` on first use.
/// Subsequent launches reuse the cached files — no re-download needed.
@MainActor
final class LocalLLMServiceMLX: LLMService {

    // ── Model configuration (set by ChatViewModel) ─────────────────────
    private(set) var modelConfiguration: ModelConfiguration

    /// Generation parameters (temperature, max tokens, etc.).
    var generateParameters: GenerateParameters = GenerateParameters(
        maxTokens: 2048, temperature: 0.6
    )

    // ── Observable state ───────────────────────────────────────────────
    private(set) var isLoaded = false
    private(set) var downloadProgress: Double = 0.0
    private(set) var statusMessage: String = "Idle"

    // ── Internal state ─────────────────────────────────────────────────
    private var modelContainer: ModelContainer?
    private var generationTask: Task<Void, Error>?

    /// Track the last system prompt used so we can rebuild the session if it changes.
    private var currentSystemPrompt: String?
    private var chatSession: ChatSession?

    // ── Init ───────────────────────────────────────────────────────────

    init(configuration: ModelConfiguration = ModelInfo.defaultModel.configuration) {
        self.modelConfiguration = configuration
    }

    // ── Loading ────────────────────────────────────────────────────────

    func load() async throws {
        guard !isLoaded else { return }

        statusMessage = "Downloading model…"
        downloadProgress = 0.0

        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: modelConfiguration
        ) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress.fractionCompleted
                let pct = Int(progress.fractionCompleted * 100)
                self?.statusMessage = "Downloading model… \(pct)%"
            }
        }

        modelContainer = container
        isLoaded = true
        downloadProgress = 1.0
        statusMessage = "Model loaded"
    }

    // ── Model switching ────────────────────────────────────────────────

    /// Tear down the current model and prepare to load a new one.
    func switchModel(to configuration: ModelConfiguration) {
        cancelGeneration()
        modelContainer = nil
        chatSession = nil
        currentSystemPrompt = nil
        isLoaded = false
        downloadProgress = 0
        modelConfiguration = configuration
        statusMessage = "Ready to load new model"
    }

    // ── Session management ─────────────────────────────────────────────

    private func session(for systemPrompt: String) -> ChatSession? {
        guard let container = modelContainer else { return nil }

        if let existing = chatSession, currentSystemPrompt == systemPrompt {
            return existing
        }

        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: generateParameters
        )
        chatSession = session
        currentSystemPrompt = systemPrompt
        return session
    }

    // ── Generation ─────────────────────────────────────────────────────

    func generateReplyStreaming(
        from messages: [ChatMessage],
        systemPrompt: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws {
        guard let session = session(for: systemPrompt) else {
            throw LLMServiceError.modelNotLoaded
        }

        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            throw LLMServiceError.noUserMessage
        }

        statusMessage = "Generating…"

        let stream = session.streamResponse(to: lastUserMessage.text)

        generationTask = Task {
            for try await chunk in stream {
                try Task.checkCancellation()
                await onToken(chunk)
            }
        }

        try await generationTask?.value
        generationTask = nil
        statusMessage = "Done"
    }

    // ── Cancellation ───────────────────────────────────────────────────

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        statusMessage = "Cancelled"
    }
}

// MARK: - Stub Implementation (no MLX required)

/// Safe stub that simulates model loading and streaming – useful for UI development.
final class LocalLLMServiceStub: LLMService {

    private(set) var isLoaded = false
    private(set) var downloadProgress: Double = 0.0
    private(set) var statusMessage: String = "Idle (stub)"

    private var generationTask: Task<Void, Never>?

    func load() async throws {
        guard !isLoaded else { return }
        statusMessage = "Loading (stub)…"
        for i in 1...5 {
            try await Task.sleep(nanoseconds: 80 * 1_000_000)
            downloadProgress = Double(i) / 5.0
        }
        isLoaded = true
        statusMessage = "Model loaded (stub)"
    }

    func generateReplyStreaming(
        from messages: [ChatMessage],
        systemPrompt: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws {
        try await load()
        statusMessage = "Generating (stub)…"

        // Echo back what context the model "sees" so you can verify the composed prompt
        let reply = "**[Stub]** System prompt has \(systemPrompt.count) chars. "
            + "Received \(messages.filter { $0.role == .user }.count) user message(s). "
            + "This is a simulated streaming reply."

        let tokens = reply.split(separator: " ").map(String.init)
        for (index, token) in tokens.enumerated() {
            try await Task.sleep(nanoseconds: UInt64.random(in: 30...100) * 1_000_000)
            try Task.checkCancellation()
            let separator = index == 0 ? "" : " "
            await onToken(separator + token)
        }
        statusMessage = "Done (stub)"
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        statusMessage = "Cancelled (stub)"
    }
}

// MARK: - Errors

enum LLMServiceError: LocalizedError {
    case modelNotLoaded
    case noUserMessage

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Model is not loaded. Call load() first."
        case .noUserMessage:  return "No user message found to respond to."
        }
    }
}
