import SwiftUI

/// Full-featured editor for managing context bubbles.
/// Shows a list with toggles, and supports add / edit / delete.
struct ContextBubbleEditor: View {
    @ObservedObject var store: ContextStore
    @State private var editingBubble: ContextBubble?
    @State private var isAddingNew = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ─────────────────────────────────────────────
            HStack {
                Text("Context Bubbles")
                    .font(.headline)
                Spacer()
                Button {
                    isAddingNew = true
                    editingBubble = ContextBubble(name: "", content: "", type: .custom, isEnabled: true)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Add a new context bubble")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // ── Bubble list by type ────────────────────────────────
            if store.bubbles.isEmpty {
                ContentUnavailableView(
                    "No Context Bubbles",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Add skills, instructions, or memory to customize the model's behavior.")
                )
            } else {
                List {
                    ForEach(ContextBubble.BubbleType.allCases) { type in
                        let items = store.bubbles.filter { $0.type == type }
                        if !items.isEmpty {
                            Section(header: Label(type.label + "s", systemImage: type.icon)) {
                                ForEach(items) { bubble in
                                    BubbleRow(bubble: bubble, store: store) {
                                        editingBubble = bubble
                                        isAddingNew = false
                                    }
                                }
                                .onDelete { offsets in
                                    let toDelete = offsets.map { items[$0] }
                                    for b in toDelete { store.delete(b) }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .sheet(item: $editingBubble) { bubble in
            BubbleDetailEditor(
                bubble: bubble,
                isNew: isAddingNew,
                onSave: { saved in
                    if isAddingNew {
                        store.add(saved)
                    } else {
                        store.update(saved)
                    }
                    editingBubble = nil
                    isAddingNew = false
                },
                onCancel: {
                    editingBubble = nil
                    isAddingNew = false
                }
            )
        }
    }
}

// MARK: - Bubble Row

private struct BubbleRow: View {
    let bubble: ContextBubble
    @ObservedObject var store: ContextStore
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { bubble.isEnabled },
                set: { _ in store.toggle(bubble) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(bubble.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(bubble.isEnabled ? .primary : .secondary)

                Text(bubble.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Bubble Detail Editor (sheet)

private struct BubbleDetailEditor: View {
    @State var bubble: ContextBubble
    let isNew: Bool
    let onSave: (ContextBubble) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(isNew ? "New Context Bubble" : "Edit Context Bubble")
                .font(.headline)

            Form {
                TextField("Name", text: $bubble.name)

                Picker("Type", selection: $bubble.type) {
                    ForEach(ContextBubble.BubbleType.allCases) { type in
                        Label(type.label, systemImage: type.icon).tag(type)
                    }
                }

                Toggle("Enabled", isOn: $bubble.isEnabled)

                VStack(alignment: .leading) {
                    Text("Content")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $bubble.content)
                        .font(.body)
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button(isNew ? "Add" : "Save") {
                    onSave(bubble)
                }
                .keyboardShortcut(.return)
                .disabled(bubble.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(minWidth: 420, minHeight: 380)
    }
}
