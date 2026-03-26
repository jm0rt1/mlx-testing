import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ChatViewModel()
    @State private var showSystemPrompt = false

    var body: some View {
        NavigationSplitView {
            ContextBubbleEditor(store: vm.contextStore)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            VStack(spacing: 0) {
                StatusBar(
                    status: vm.status,
                    isDownloading: vm.isDownloading,
                    progress: vm.downloadProgress,
                    enabledContextCount: vm.contextStore.bubbles.filter(\.isEnabled).count,
                    modelName: vm.catalog.find(id: vm.selectedModelID)?.displayName
                        ?? vm.selectedModelID.components(separatedBy: "/").last ?? "Unknown",
                    toolsEnabled: vm.toolsEnabled,
                    toolCount: vm.toolRegistry.tools.count
                )

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(vm.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal)
                    }
                    .onChange(of: vm.messages.last?.text) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: vm.messages.count) {
                        scrollToBottom(proxy: proxy)
                    }
                }

                Divider()

                InputBar(
                    input: $vm.input,
                    isLoading: vm.isLoading,
                    onSend: { Task { await vm.send() } },
                    onCancel: { vm.cancelGeneration() }
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ModelPickerView(selectedModelID: $vm.selectedModelID, catalog: vm.catalog)
                    .disabled(vm.isLoading)
            }

            ToolbarItemGroup(placement: .automatic) {
                Toggle(isOn: $vm.toolsEnabled) {
                    Label("Tools", systemImage: vm.toolsEnabled ? "hammer.fill" : "hammer")
                }
                .toggleStyle(.button)
                .help(vm.toolsEnabled
                      ? "Agent tools enabled (\(vm.toolRegistry.tools.count) tools)"
                      : "Agent tools disabled")

                Button {
                    showSystemPrompt = true
                } label: {
                    Label("System Prompt", systemImage: "terminal")
                }
                .help("Edit system prompt & view composed context")

                Picker("Backend", selection: $vm.backend) {
                    ForEach(LLMBackend.allCases) { b in
                        Text(b.rawValue).tag(b)
                    }
                }
                .pickerStyle(.menu)
                .help("Switch between real MLX model and stub")

                Button(action: { vm.clearConversation() }) {
                    Label("Clear", systemImage: "trash")
                }
                .help("Clear conversation")
            }
        }
        .sheet(isPresented: $showSystemPrompt) {
            SystemPromptEditor(store: vm.contextStore)
        }
        .sheet(isPresented: $vm.showToolApproval) {
            ToolApprovalSheet(vm: vm)
        }
        .task {
            await vm.loadCatalog()
            await vm.loadModelIfNeeded()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = vm.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Tool Approval Sheet

private struct ToolApprovalSheet: View {
    @ObservedObject var vm: ChatViewModel

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: riskIcon)
                    .font(.title)
                    .foregroundStyle(riskColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tool Approval Required")
                        .font(.headline)
                    if let call = vm.pendingToolCall {
                        Text("**\(call.toolName)** wants to execute")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)

            Divider()

            if let call = vm.pendingToolCall {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Arguments")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(call.arguments.keys.sorted()), id: \.self) { key in
                        HStack(alignment: .top) {
                            Text(key)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .trailing)
                            Text(call.arguments[key]?.stringValue ?? "—")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                if let tool = vm.toolRegistry.tool(named: call.toolName) {
                    if tool.riskLevel >= .medium {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(riskDescription(for: tool.riskLevel))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button("Deny") {
                    vm.respondToApproval(.deny)
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Always Allow") {
                    vm.respondToApproval(.alwaysApprove)
                }
                .foregroundStyle(.secondary)

                Button("Allow") {
                    vm.respondToApproval(.approve)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(width: 480)
        .interactiveDismissDisabled()
    }

    private var riskIcon: String {
        guard let call = vm.pendingToolCall,
              let tool = vm.toolRegistry.tool(named: call.toolName) else {
            return "questionmark.circle"
        }
        switch tool.riskLevel {
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.shield"
        case .high: return "xmark.shield"
        }
    }

    private var riskColor: Color {
        guard let call = vm.pendingToolCall,
              let tool = vm.toolRegistry.tool(named: call.toolName) else {
            return .secondary
        }
        switch tool.riskLevel {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private func riskDescription(for level: ToolRiskLevel) -> String {
        switch level {
        case .low: return "Low risk — reads only, no system changes."
        case .medium: return "Medium risk — may modify files or launch applications."
        case .high: return "High risk — executes shell commands on your system."
        }
    }
}

// MARK: - Status Bar

private struct StatusBar: View {
    let status: String
    let isDownloading: Bool
    let progress: Double
    let enabledContextCount: Int
    let modelName: String
    let toolsEnabled: Bool
    let toolCount: Int

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .imageScale(.small)

                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "cpu")
                        .imageScale(.small)
                    Text(modelName)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                if enabledContextCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .imageScale(.small)
                        Text("\(enabledContextCount) context\(enabledContextCount == 1 ? "" : "s")")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tint)
                }

                if toolsEnabled {
                    HStack(spacing: 3) {
                        Image(systemName: "hammer.fill")
                            .imageScale(.small)
                        Text("\(toolCount) tools")
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if isDownloading {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .padding(.horizontal)
            }
        }
        .padding(.bottom, 6)
    }

    private var statusIcon: String {
        if isDownloading { return "arrow.down.circle" }
        if status.contains("loaded") || status.contains("Done") { return "checkmark.circle.fill" }
        if status.contains("fail") || status.contains("Failed") { return "exclamationmark.triangle.fill" }
        if status.contains("Generating") { return "sparkle" }
        if status.contains("Tool") { return "hammer" }
        if status.contains("Executing") { return "gearshape.2" }
        return "bolt.fill"
    }

    private var statusColor: Color {
        if status.contains("fail") || status.contains("Failed") || status.contains("denied") { return .red }
        if status.contains("loaded") || status.contains("Done") { return .green }
        if isDownloading || status.contains("Generating") { return .orange }
        if status.contains("Tool") || status.contains("Executing") { return .purple }
        return .secondary
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .toolCall:
            toolCallBubble
        case .toolResult:
            toolResultBubble
        case .system:
            EmptyView()
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                Text("You")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(message.text.isEmpty ? "…" : message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var assistantBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Assistant")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                MarkdownView(text: message.text.isEmpty ? "…" : message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Spacer(minLength: 60)
        }
    }

    private var toolCallBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: toolCallIcon)
                        .foregroundStyle(toolCallColor)
                    Text("Tool: \(message.toolCall?.toolName ?? "unknown")")
                        .font(.caption.bold())
                    Spacer()
                    Text(toolCallStatusLabel)
                        .font(.caption2)
                        .foregroundStyle(toolCallColor)
                }

                if let args = message.toolCall?.arguments, !args.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(args.keys.sorted()), id: \.self) { key in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(key):")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(args[key] ?? "")
                                    .font(.caption2.monospaced())
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
            Spacer(minLength: 40)
        }
    }

    private var toolResultBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: message.toolResult?.success == true
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(message.toolResult?.success == true ? .green : .red)
                    Text("Result: \(message.toolResult?.toolName ?? "unknown")")
                        .font(.caption.bold())
                    Spacer()
                    if let result = message.toolResult {
                        Text(result.success ? "Success" : "Failed")
                            .font(.caption2)
                            .foregroundStyle(result.success ? .green : .red)
                    }
                }

                Text(message.text.isEmpty ? "…" : message.text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                if let artifacts = message.toolResult?.artifacts, !artifacts.isEmpty {
                    ForEach(Array(artifacts.enumerated()), id: \.offset) { _, artifact in
                        HStack(spacing: 4) {
                            Image(systemName: artifactIcon(artifact.type))
                                .imageScale(.small)
                            Text(artifact.label)
                                .font(.caption2)
                            Text(artifact.value)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((message.toolResult?.success == true ? Color.green : Color.red).opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke((message.toolResult?.success == true ? Color.green : Color.red).opacity(0.2), lineWidth: 1)
            )
            Spacer(minLength: 40)
        }
    }

    private var toolCallIcon: String {
        switch message.toolCall?.status {
        case .pending: return "clock"
        case .approved, .executing: return "gearshape.2"
        case .completed: return "checkmark.circle.fill"
        case .denied: return "hand.raised.fill"
        case .failed: return "xmark.circle.fill"
        case nil: return "questionmark.circle"
        }
    }

    private var toolCallColor: Color {
        switch message.toolCall?.status {
        case .pending: return .orange
        case .approved, .executing: return .purple
        case .completed: return .green
        case .denied, .failed: return .red
        case nil: return .secondary
        }
    }

    private var toolCallStatusLabel: String {
        switch message.toolCall?.status {
        case .pending: return "Pending…"
        case .approved: return "Approved"
        case .executing: return "Executing…"
        case .completed: return "Complete"
        case .denied: return "Denied"
        case .failed: return "Failed"
        case nil: return ""
        }
    }

    private func artifactIcon(_ type: ToolArtifact.ArtifactType) -> String {
        switch type {
        case .filePath: return "doc"
        case .url: return "link"
        case .text: return "text.quote"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - Input Bar

private struct InputBar: View {
    @Binding var input: String
    let isLoading: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Type a message…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .lineLimit(1...8)
                .onSubmit {
                    if !isLoading { onSend() }
                }

            if isLoading {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop generation")
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(10)
    }
}

#Preview {
    ContentView()
}
