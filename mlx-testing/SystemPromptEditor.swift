import SwiftUI

/// Sheet for editing the base system prompt.
/// Also shows a read-only preview of the full composed prompt (base + enabled contexts).
struct SystemPromptEditor: View {
    @ObservedObject var store: ContextStore
    @Environment(\.dismiss) private var dismiss
    @State private var showComposed = false

    var body: some View {
        VStack(spacing: 16) {
            Text("System Prompt")
                .font(.headline)

            // ── Base prompt editor ─────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("Base Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $store.systemPrompt)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2))
                    )
            }

            // ── Toggle to see the full composed prompt ─────────────
            DisclosureGroup("Composed Prompt Preview", isExpanded: $showComposed) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This is what the model actually receives (base + enabled context bubbles):")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(store.composedSystemPrompt)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 200)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("\(store.composedSystemPrompt.count) characters")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // ── Active contexts summary ────────────────────────────
            let enabledCount = store.bubbles.filter(\.isEnabled).count
            let totalCount = store.bubbles.count
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(.secondary)
                Text("\(enabledCount) of \(totalCount) context bubbles enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Divider()

            // ── Buttons ────────────────────────────────────────────
            HStack {
                Button("Reset to Default") {
                    store.systemPrompt = "You are a friendly, concise, and helpful assistant."
                }
                .foregroundStyle(.red)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 340)
    }
}
