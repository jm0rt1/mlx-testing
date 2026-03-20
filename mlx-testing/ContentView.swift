import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ChatViewModel()
    @State private var showSystemPrompt = false
    @State private var showSidebar = true

    var body: some View {
        NavigationSplitView {
            // ── Sidebar: Context Bubbles ────────────────────────────
            ContextBubbleEditor(store: vm.contextStore)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            // ── Main: Chat Area ────────────────────────────────────
            VStack(spacing: 0) {
                StatusBar(
                    status: vm.status,
                    isDownloading: vm.isDownloading,
                    progress: vm.downloadProgress,
                    enabledContextCount: vm.contextStore.bubbles.filter(\.isEnabled).count
                )

                Divider()

                // ── Messages ───────────────────────────────────────
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

                // ── Input ──────────────────────────────────────────
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
            ToolbarItemGroup(placement: .automatic) {
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
        .task { await vm.loadModelIfNeeded() }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = vm.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Status Bar

private struct StatusBar: View {
    let status: String
    let isDownloading: Bool
    let progress: Double
    let enabledContextCount: Int

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

                // Context indicator
                if enabledContextCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .imageScale(.small)
                        Text("\(enabledContextCount) context\(enabledContextCount == 1 ? "" : "s")")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tint)
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
        return "bolt.fill"
    }

    private var statusColor: Color {
        if status.contains("fail") || status.contains("Failed") { return .red }
        if status.contains("loaded") || status.contains("Done") { return .green }
        if isDownloading || status.contains("Generating") { return .orange }
        return .secondary
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.role == .user ? "You" : "Assistant")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(message.text.isEmpty ? "…" : message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            Color.accentColor.opacity(0.15)
        } else {
            Color(.controlBackgroundColor)
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

// MARK: - Preview

#Preview {
    ContentView()
}
