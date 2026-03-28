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

    /// Debug log entries for the agentic loop — visible in the UI debug console.
    @Published private(set) var debugLog: [String] = []
    @Published var showDebugConsole: Bool = false

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
        // /no_think suppresses chain-of-thought output on Qwen3 models
        var prompt = "/no_think\n\n"

        // Inject current date/time so the model can resolve relative references
        let now = Date()
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEEE"
        prompt += "[Current Date & Time]\n"
        prompt += "Today is \(dayFmt.string(from: now)), \(dateFmt.string(from: now)). "
        prompt += "The current time is \(timeFmt.string(from: now)).\n"
        prompt += "When the user says 'tomorrow', use \(dateFmt.string(from: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now)).\n"
        prompt += "Always use ISO 8601 format (e.g. \(dateFmt.string(from: now))T09:00:00) for dates in tool calls.\n\n"

        prompt += contextStore.composedSystemPrompt

        if toolsEnabled && !toolRegistry.enabledTools.isEmpty {
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
        isCancelled = false
        status = "Generating…"

        await agenticLoop()

        isLoading = false
    }

    /// Tracks whether generation was cancelled.
    private var isCancelled = false

    /// The core agentic loop: generate → check for tool calls → execute → feed back → repeat.
    private func agenticLoop() async {
        var iterations = 0

        // The first prompt is the user's message; subsequent prompts are tool results
        guard let userMessage = messages.last(where: { $0.role == .user })?.text else { return }
        var currentPrompt = userMessage

        while iterations < maxToolIterations && !isCancelled {
            iterations += 1
            appendDebug("── Iteration \(iterations) ──")
            appendDebug("Prompt (\(currentPrompt.count) chars): \(currentPrompt.prefix(300))")

            // 1) Generate assistant response
            let assistantID = UUID()
            messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))

            let composedPrompt = fullSystemPrompt

            do {
                try await llmService.generateReplyStreaming(
                    prompt: currentPrompt,
                    systemPrompt: composedPrompt
                ) { [weak self] token in
                    guard let self else { return }
                    if let idx = self.messages.lastIndex(where: { $0.id == assistantID }) {
                        self.messages[idx].text += token
                    }
                }

                // Sanitize the complete response
                if let idx = messages.lastIndex(where: { $0.id == assistantID }) {
                    messages[idx].text = Self.sanitizeResponse(messages[idx].text)
                }
            } catch is CancellationError {
                status = "Cancelled"
                appendDebug("❌ Generation cancelled")
                return
            } catch {
                if let idx = messages.lastIndex(where: { $0.id == assistantID }) {
                    messages[idx].text = "⚠️ \(error.localizedDescription)"
                }
                status = "Generation failed"
                appendDebug("❌ Generation error: \(error.localizedDescription)")
                return
            }

            guard !isCancelled else {
                status = "Cancelled"
                return
            }

            // 2) Check if the response contains a tool call
            guard toolsEnabled else {
                status = "Done"
                appendDebug("Tools disabled — done.")
                return
            }

            guard let idx = messages.lastIndex(where: { $0.id == assistantID }) else {
                status = "Done"
                return
            }
            let fullResponse = messages[idx].text
            appendDebug("Response (\(fullResponse.count) chars): \(fullResponse.prefix(500))")

            // Hex dump to catch non-standard backtick characters
            let bytes = Array(fullResponse.utf8)
            let hexFirst = bytes.prefix(40).map { String(format: "%02x", $0) }.joined(separator: " ")
            let hexLast = bytes.suffix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
            appendDebug("Hex (first 40): \(hexFirst)")
            appendDebug("Hex (last 20): \(hexLast)")
            appendDebug("Contains backtick (0x60): \(fullResponse.contains("`"))")
            appendDebug("Contains 'tool_call': \(fullResponse.contains("tool_call"))")
            appendDebug("Contains '\"tool\"': \(fullResponse.contains("\"tool\""))")

            guard let toolCall = toolExecutor.parseToolCall(from: fullResponse) else {
                appendDebug("✅ No tool call found — done.")
                status = "Done"
                return
            }

            appendDebug("🔧 Parsed tool call: \(toolCall.toolName)")
            appendDebug("   Args: \(toolCall.arguments.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")

            // 2b) Reject calls to disabled tools early (before approval flow)
            guard toolRegistry.isToolEnabled(toolCall.toolName) else {
                appendDebug("⛔ Tool '\(toolCall.toolName)' is disabled — skipping.")
                let prose = toolExecutor.extractProse(from: fullResponse)
                messages[idx].text = prose.isEmpty ? "Tried to call disabled tool: \(toolCall.toolName)" : prose
                messages.append(ChatMessage(
                    role: .toolResult,
                    text: "⛔ Tool '\(toolCall.toolName)' is currently disabled.",
                    toolResult: ToolResultInfo(toolName: toolCall.toolName, success: false, output: "Tool is disabled by user.", artifacts: [])
                ))
                status = "Tool disabled"
                return
            }

            // 3) Extract prose and update the assistant message
            let prose = toolExecutor.extractProse(from: fullResponse)
            messages[idx].text = prose.isEmpty ? "Calling tool: \(toolCall.toolName)…" : prose

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
            if toolRegistry.needsApproval(for: toolCall.toolName) {
                appendDebug("⏳ Waiting for user approval…")
                let response = await requestApproval(for: toolCall)

                switch response {
                case .deny:
                    appendDebug("⛔ User denied tool call")
                    if let ci = messages.lastIndex(where: { $0.id == callMsgID }) {
                        messages[ci].toolCall?.status = .denied
                    }
                    messages.append(ChatMessage(
                        role: .toolResult,
                        text: "⛔ Tool call denied by user.",
                        toolResult: ToolResultInfo(toolName: toolCall.toolName, success: false, output: "User denied execution.", artifacts: [])
                    ))
                    status = "Tool denied"
                    return

                case .approve:
                    appendDebug("✅ User approved")
                    break

                case .alwaysApprove:
                    appendDebug("✅ User approved (always)")
                    toolRegistry.alwaysApproved.insert(toolCall.toolName)
                }
            } else {
                appendDebug("✅ Auto-approved (always approved)")
            }

            // 6) Execute the tool
            if let ci = messages.lastIndex(where: { $0.id == callMsgID }) {
                messages[ci].toolCall?.status = .executing
            }
            status = "Executing \(toolCall.toolName)…"
            appendDebug("⚙️ Executing \(toolCall.toolName)…")

            do {
                let result = try await toolExecutor.execute(toolCall)
                appendDebug("✅ Tool result: \(result.success ? "success" : "failure")")
                appendDebug("   Output (\(result.output.count) chars): \(result.output.prefix(300))")

                if let ci = messages.lastIndex(where: { $0.id == callMsgID }) {
                    messages[ci].toolCall?.status = .completed
                }

                let resultText = result.output
                messages.append(ChatMessage(
                    role: .toolResult,
                    text: resultText,
                    toolResult: ToolResultInfo(toolName: result.toolName, success: result.success, output: result.output, artifacts: result.artifacts)
                ))
                status = "Tool complete — continuing…"

                // KEY FIX: Feed the tool result back to the model as the next prompt
                // Truncate large outputs to prevent the model from choking
                let maxResultChars = 3000
                let truncatedOutput: String
                if result.output.count > maxResultChars {
                    truncatedOutput = String(result.output.prefix(maxResultChars)) + "\n… (output truncated, \(result.output.count) total chars)"
                } else {
                    truncatedOutput = result.output
                }

                currentPrompt = """
                /no_think
                [Tool Result from \(result.toolName)] \(result.success ? "Success" : "Failed"):
                \(truncatedOutput)

                Summarize this result for the user concisely.
                """
                appendDebug("📤 Feeding tool result back as next prompt (\(currentPrompt.count) chars)")

            } catch {
                appendDebug("❌ Tool error: \(error.localizedDescription)")
                if let ci = messages.lastIndex(where: { $0.id == callMsgID }) {
                    messages[ci].toolCall?.status = .failed
                }
                messages.append(ChatMessage(
                    role: .toolResult,
                    text: "❌ Tool error: \(error.localizedDescription)",
                    toolResult: ToolResultInfo(toolName: toolCall.toolName, success: false, output: error.localizedDescription, artifacts: [])
                ))
                status = "Tool failed"
                return
            }

            // 7) Loop back — currentPrompt is now the tool result
        }

        status = iterations >= maxToolIterations ? "Done (max tool iterations reached)" : "Done"
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
        isCancelled = true
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

    // ── Debug logging ────────────────────────────────────────────────────

    private func appendDebug(_ message: String) {
        let ts = Self.debugDateFormatter.string(from: Date())
        let entry = "[\(ts)] \(message)"
        debugLog.append(entry)
        print("[Debug] \(entry)")
        // Keep last 500 entries
        if debugLog.count > 500 {
            debugLog.removeFirst(debugLog.count - 500)
        }
    }

    func clearDebugLog() {
        debugLog = []
    }

    private static let debugDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
}
