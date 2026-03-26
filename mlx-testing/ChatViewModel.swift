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

    /// Whether the agentic tool system is enabled.
    @Published var toolsEnabled: Bool = true

    /// Toggle between MLX and stub back-ends.
    @Published var backend: LLMBackend {
        didSet { switchService() }
    }

    /// Currently selected model ID (persisted via UserDefaults).
    @Published var selectedModelID: String {
        didSet {
            UserDefaults.standard.set(selectedModelID, forKey: "selectedModelID")
            if oldValue != selectedModelID {
                switchModel()
            }
        }
    }

    // ── Tool system ────────────────────────────────────────────────────
    let toolRegistry = ToolRegistry.shared
    let toolExecutor: ToolExecutor

    /// Set by the UI when the user responds to a tool approval prompt.
    @Published var pendingToolCall: ToolCall?
    @Published var showToolApproval: Bool = false

    /// Continuation for the approval flow — resumed when user approves/denies.
    private var approvalContinuation: CheckedContinuation<ToolApprovalResponse, Never>?

    // ── Context store (shared with UI) ─────────────────────────────────
    let contextStore = ContextStore()

    /// Dynamic model catalog — fetched from HF API, persisted to disk.
    let catalog = ModelCatalogService()

    // ── Private state ──────────────────────────────────────────────────
    private var llmService: LLMService
    private var generationTask: Task<Void, Never>?

    /// Max agentic loop iterations to prevent runaway tool calling.
    private let maxToolIterations = 10

    // ── Init ───────────────────────────────────────────────────────────

    init(backend: LLMBackend = .mlx) {
        self.backend = backend
        self.toolExecutor = ToolExecutor(registry: ToolRegistry.shared)

        let savedID = UserDefaults.standard.string(forKey: "selectedModelID")
        let modelID = savedID ?? ModelCatalogService.defaultModelID
        self.selectedModelID = modelID

        if backend == .mlx {
            self.llmService = LocalLLMServiceMLX(modelID: modelID)
        } else {
            self.llmService = LocalLLMServiceStub()
        }

        // Register built-in tools
        toolRegistry.registerDefaults()
    }

    // ── Catalog loading ────────────────────────────────────────────────

    func loadCatalog() async {
        await catalog.loadAndRefreshIfNeeded()
    }

    // ── Switch back-end ────────────────────────────────────────────────

    private func switchService() {
        cancelGeneration()
        if backend == .mlx {
            llmService = LocalLLMServiceMLX(modelID: selectedModelID)
        } else {
            llmService = LocalLLMServiceStub()
        }
        messages = []
        status = "Switched to \(backend.rawValue)"
        isLoading = false
        downloadProgress = 0
        isDownloading = false
    }

    // ── Switch model ───────────────────────────────────────────────────

    private func switchModel() {
        cancelGeneration()

        if backend == .mlx, let mlxService = llmService as? LocalLLMServiceMLX {
            mlxService.switchModel(to: selectedModelID)
            messages = []
            status = "Model changed — loading…"
            isLoading = false
            downloadProgress = 0
            isDownloading = false
            Task { await loadModelIfNeeded() }
        }
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

    // ── Composed system prompt (includes tool schemas when enabled) ────

    private var fullSystemPrompt: String {
        var prompt = contextStore.composedSystemPrompt

        if toolsEnabled && !toolRegistry.tools.isEmpty {
            prompt += "\n\n" + toolRegistry.toolSchemaPrompt()
        }

        return prompt
    }

    // ── Send message (with agentic loop) ───────────────────────────────

    func send() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        input = ""
        isLoading = true
        status = "Generating…"

        await agenticLoop()

        isLoading = false
    }

    /// The core agentic loop: generate → check for tool calls → execute → feed back → repeat.
    private func agenticLoop() {
        generationTask = Task {
            var iterations = 0

            while iterations < maxToolIterations {
                iterations += 1

                // 1) Generate assistant response
                let assistantID = UUID()
                messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))

                let composedPrompt = fullSystemPrompt

                do {
                    try await llmService.generateReplyStreaming(
                        from: messages,
                        systemPrompt: composedPrompt
                    ) { [weak self] token in
                        guard let self else { return }
                        if let idx = self.messages.lastIndex(where: { $0.id == assistantID }) {
                            self.messages[idx].text += token
                            self.messages[idx].text = Self.sanitizeResponse(self.messages[idx].text)
                        }
                    }

                    // Final sanitize
                    if let idx = messages.lastIndex(where: { $0.id == assistantID }) {
                        messages[idx].text = Self.sanitizeResponse(messages[idx].text)
                    }
                } catch is CancellationError {
                    status = "Cancelled"
                    return
                } catch {
                    if let idx = messages.lastIndex(where: { $0.id == assistantID }) {
                        messages[idx].text = "⚠️ \(error.localizedDescription)"
                    }
                    status = "Generation failed"
                    return
                }

                // 2) Check if the response contains a tool call
                guard toolsEnabled else {
                    status = "Done"
                    return
                }

                let fullResponse = messages.first(where: { $0.id == assistantID })?.text ?? ""
                guard let toolCall = toolExecutor.parseToolCall(from: fullResponse) else {
                    // No tool call — normal response, we're done
                    status = "Done"
                    return
                }

                // 3) Extract prose and update the assistant message
                let prose = toolExecutor.extractProse(from: fullResponse)
                if let idx = messages.lastIndex(where: { $0.id == assistantID }) {
                    messages[idx].text = prose.isEmpty ? "Calling tool: \(toolCall.toolName)…" : prose
                }

                // 4) Add a tool call bubble
                let flatArgs = toolCall.arguments.mapValues { $0.stringValue }
                let callInfo = ToolCallInfo(
                    toolName: toolCall.toolName,
                    arguments: flatArgs,
                    status: .pending
                )
                let callMsgID = UUID()
                messages.append(ChatMessage(
                    id: callMsgID,
                    role: .toolCall,
                    text: "🔧 \(toolCall.toolName)",
                    toolCall: callInfo
                ))

                status = "Tool: \(toolCall.toolName) — awaiting approval…"

                // 5) Check approval
                let needsApproval = toolRegistry.needsApproval(for: toolCall.toolName)

                if needsApproval {
                    // Ask user for approval
                    let response = await requestApproval(for: toolCall)

                    switch response {
                    case .deny:
                        if let idx = messages.lastIndex(where: { $0.id == callMsgID }) {
                            messages[idx].toolCall?.status = .denied
                        }
                        messages.append(ChatMessage(
                            role: .toolResult,
                            text: "⛔ Tool call denied by user.",
                            toolResult: ToolResultInfo(
                                toolName: toolCall.toolName,
                                success: false,
                                output: "User denied execution.",
                                artifacts: []
                            )
                        ))
                        status = "Tool denied"
                        return

                    case .approve:
                        break // continue to execute

                    case .alwaysApprove:
                        toolRegistry.alwaysApproved.insert(toolCall.toolName)
                    }
                }

                // 6) Execute the tool
                if let idx = messages.lastIndex(where: { $0.id == callMsgID }) {
                    messages[idx].toolCall?.status = .executing
                }
                status = "Executing \(toolCall.toolName)…"

                do {
                    let result = try await toolExecutor.execute(toolCall)

                    // Update call status
                    if let idx = messages.lastIndex(where: { $0.id == callMsgID }) {
                        messages[idx].toolCall?.status = .completed
                    }

                    // Add result bubble
                    let resultInfo = ToolResultInfo(
                        toolName: result.toolName,
                        success: result.success,
                        output: result.output,
                        artifacts: result.artifacts
                    )
                    messages.append(ChatMessage(
                        role: .toolResult,
                        text: result.output,
                        toolResult: resultInfo
                    ))

                    status = "Tool complete — continuing…"

                } catch {
                    if let idx = messages.lastIndex(where: { $0.id == callMsgID }) {
                        messages[idx].toolCall?.status = .failed
                    }
                    messages.append(ChatMessage(
                        role: .toolResult,
                        text: "❌ Tool error: \(error.localizedDescription)",
                        toolResult: ToolResultInfo(
                            toolName: toolCall.toolName,
                            success: false,
                            output: error.localizedDescription,
                            artifacts: []
                        )
                    ))
                    status = "Tool failed"
                    return
                }

                // 7) Loop back: the model will see the tool result and can respond or call another tool
            }

            status = "Done (max tool iterations reached)"
        }

        // Await the task
        Task {
            await generationTask?.value
        }
    }

    // ── Tool Approval Flow ─────────────────────────────────────────────

    enum ToolApprovalResponse {
        case approve
        case deny
        case alwaysApprove
    }

    /// Suspends until the user taps approve/deny in the UI.
    private func requestApproval(for call: ToolCall) async -> ToolApprovalResponse {
        pendingToolCall = call
        showToolApproval = true

        return await withCheckedContinuation { continuation in
            self.approvalContinuation = continuation
        }
    }

    /// Called by the UI when user responds to the approval prompt.
    func respondToApproval(_ response: ToolApprovalResponse) {
        showToolApproval = false
        pendingToolCall = nil
        approvalContinuation?.resume(returning: response)
        approvalContinuation = nil
    }

    // ── Response sanitizer ─────────────────────────────────────────────

    private static func sanitizeResponse(_ text: String) -> String {
        var result = text

        result = result.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: .regularExpression
        )

        if result.contains("<think>") && !result.contains("</think>") {
            if let range = result.range(of: "<think>") {
                result = String(result[result.startIndex..<range.lowerBound])
            }
        }

        result = result.replacingOccurrences(
            of: #"<reasoning>[\s\S]*?</reasoning>"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"<\/?(?:think|reasoning)>"#,
            with: "",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    // ── Cancel generation ──────────────────────────────────────────────

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        llmService.cancelGeneration()
        isLoading = false
        status = "Cancelled"

        // Also cancel any pending approval
        if showToolApproval {
            respondToApproval(.deny)
        }
    }

    // ── Clear conversation ─────────────────────────────────────────────

    func clearConversation() {
        cancelGeneration()
        messages = []
        toolExecutor.clearHistory()
        status = llmService.isLoaded ? "Model loaded" : "Idle"
    }
}
