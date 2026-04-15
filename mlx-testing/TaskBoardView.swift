import SwiftUI

struct TaskBoardView: View {
    @ObservedObject var store: TaskBoardStore

    @State private var showEditor = false
    @State private var editingItem: TaskBoardItem?
    @State private var draft = TaskBoardDraft()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Task Board")
                    .font(.headline)
                Spacer()
                Button {
                    draft = TaskBoardDraft()
                    editingItem = nil
                    showEditor = true
                } label: {
                    Label("Add Goal", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("Add goal")
            }
            .padding([.horizontal, .top])

            List {
                section("Active", items: store.activeItems)
                section("Backlog", items: store.backlogItems)
                section("Maintenance", items: store.maintenanceItems)
                section("Completed", items: store.completedItems)
            }
            .listStyle(.sidebar)
        }
        .sheet(isPresented: $showEditor) {
            TaskBoardEditorSheet(
                draft: $draft,
                isEditing: editingItem != nil,
                onSave: {
                    if let editingItem {
                        var updated = editingItem
                        updated.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.nextAction = draft.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.tags = draft.tags.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.status = draft.status
                        store.update(updated)
                    } else {
                        let item = TaskBoardItem(
                            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                            nextAction: draft.nextAction.trimmingCharacters(in: .whitespacesAndNewlines),
                            tags: draft.tags.trimmingCharacters(in: .whitespacesAndNewlines),
                            status: draft.status
                        )
                        store.add(item)
                    }
                    showEditor = false
                }
            )
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [TaskBoardItem]) -> some View {
        Section(title) {
            if items.isEmpty {
                Text("No items")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(items) { item in
                    TaskBoardRow(
                        item: item,
                        onActivate: { store.promoteToActive(item) },
                        onComplete: { store.markCompleted(item) },
                        onEdit: {
                            editingItem = item
                            draft = TaskBoardDraft(item: item)
                            showEditor = true
                        },
                        onDelete: { store.delete(item) }
                    )
                }
            }
        }
    }
}

private struct TaskBoardRow: View {
    let item: TaskBoardItem
    let onActivate: () -> Void
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    if !item.nextAction.isEmpty {
                        Text(item.nextAction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !item.tags.isEmpty {
                        Text(item.tags)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                if item.status != .active {
                    Button("Make Active", action: onActivate)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                if item.status != .completed {
                    Button("Complete", action: onComplete)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                Button("Edit", action: onEdit)
                    .buttonStyle(.borderless)
                    .font(.caption)
                Button(role: .destructive, action: onDelete) {
                    Text("Delete")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TaskBoardDraft {
    var title: String = ""
    var nextAction: String = ""
    var tags: String = ""
    var status: TaskStatus = .backlog

    init() {}

    init(item: TaskBoardItem) {
        title = item.title
        nextAction = item.nextAction
        tags = item.tags
        status = item.status
    }
}

private struct TaskBoardEditorSheet: View {
    @Binding var draft: TaskBoardDraft
    let isEditing: Bool
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $draft.title)
                TextField("Next action", text: $draft.nextAction)
                TextField("Tags", text: $draft.tags)
                Picker("Status", selection: $draft.status) {
                    ForEach(TaskStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Goal" : "Add Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        onSave()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
    }
}
