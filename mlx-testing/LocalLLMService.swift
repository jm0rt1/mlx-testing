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
    /// Generate a streaming response to `prompt`. The prompt is a single string
    /// (either the user's message or a tool-result injection).
    func generateReplyStreaming(
        prompt: String,
        systemPrompt: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws
    func cancelGeneration()
}

// MARK: - MLX-backed Implementation

/// Real MLX Swift LM service that creates a ModelConfiguration dynamically
/// from a Hugging Face model ID string — no hardcoded catalog needed.
///
/// **Model caching**: MLX downloads weights to the app's Caches directory on first use.
/// Subsequent launches reuse the cached files automatically.
@MainActor
final class LocalLLMServiceMLX: LLMService {

    // MARK: - State

    /// The HF model ID, e.g. "mlx-community/Qwen3-8B-4bit"
    private(set) var modelID: String

    var generateParameters: GenerateParameters = GenerateParameters(
        maxTokens: 2048, temperature: 0.6
    )

    private(set) var isLoaded = false
    private(set) var downloadProgress: Double = 0.0
    private(set) var statusMessage: String = "Idle"

    private var modelContainer: ModelContainer?
    private var generationTask: Task<Void, Error>?
    private var currentSystemPrompt: String?
    private var chatSession: ChatSession?

    // MARK: - Init

    /// Initialize with a HuggingFace model ID. The ModelConfiguration is created dynamically.
    init(modelID: String = ModelCatalogService.defaultModelID) {
        self.modelID = modelID
    }

    // MARK: - Loading

    func load() async throws {
        guard !isLoaded else { return }

        statusMessage = "Downloading model…"
        downloadProgress = 0.0

        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

        // Create ModelConfiguration dynamically from the HF repo ID
        let configuration = ModelConfiguration(id: modelID)

        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: configuration
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

    // MARK: - Model switching

    /// Tear down the current model and prepare to load a new one.
    func switchModel(to newModelID: String) {
        cancelGeneration()
        modelContainer = nil
        chatSession = nil
        currentSystemPrompt = nil
        isLoaded = false
        downloadProgress = 0
        modelID = newModelID
        statusMessage = "Ready to load \(newModelID.components(separatedBy: "/").last ?? newModelID)"
    }

    // MARK: - Session management

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

    // MARK: - Generation

    func generateReplyStreaming(
        prompt: String,
        systemPrompt: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws {
        guard let session = session(for: systemPrompt) else {
            throw LLMServiceError.modelNotLoaded
        }

        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMServiceError.noUserMessage
        }

        statusMessage = "Generating…"

        let stream = session.streamResponse(to: prompt)

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

    // MARK: - Cancellation

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        statusMessage = "Cancelled"
    }
}

// MARK: - Stub Implementation (no MLX required)

/// Safe stub that simulates model loading and streaming — useful for UI development.
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
        prompt: String,
        systemPrompt: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws {
        try await load()
        statusMessage = "Generating (stub)…"

        let reply = "**[Stub]** System prompt has \(systemPrompt.count) chars. "
            + "Prompt: \(prompt.prefix(100)). "
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
