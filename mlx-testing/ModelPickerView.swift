import SwiftUI

/// A toolbar-style picker that opens a popover showing all available models
/// with download status, disk/RAM sizes, and notes.
struct ModelPickerView: View {
    @Binding var selectedModelID: String

    @State private var showPopover = false
    @State private var refreshID = UUID()
    @State private var searchText = ""

    private var selectedModel: ModelInfo {
        ModelInfo.find(id: selectedModelID) ?? ModelInfo.defaultModel
    }

    private var filteredCatalog: [ModelInfo] {
        if searchText.isEmpty { return ModelInfo.catalog }
        let q = searchText.lowercased()
        return ModelInfo.catalog.filter {
            $0.displayName.lowercased().contains(q)
            || $0.family.lowercased().contains(q)
            || $0.parameterLabel.lowercased().contains(q)
            || $0.id.lowercased().contains(q)
        }
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Label(selectedModel.displayName, systemImage: "cpu")
        }
        .help("Select model — \(selectedModel.displayName) (\(selectedModel.diskSizeLabel))")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search models…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)

                Divider()

                // Model list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(ModelInfo.families, id: \.self) { family in
                            let items = filteredCatalog.filter { $0.family == family }
                            if !items.isEmpty {
                                // Section header
                                HStack {
                                    Text(family)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                                .padding(.bottom, 4)

                                ForEach(items) { model in
                                    ModelRow(
                                        model: model,
                                        isSelected: model.id == selectedModelID,
                                        refreshID: refreshID
                                    ) {
                                        selectedModelID = model.id
                                        showPopover = false
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }

                Divider()

                // Footer
                HStack {
                    Button {
                        refreshID = UUID()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(ModelInfo.catalog.count) models available")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(width: 420, height: 480)
        }
    }
}

// MARK: - Model Row (inside popover)

private struct ModelRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let refreshID: UUID
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Download status icon
                let downloaded = model.isDownloaded
                Image(systemName: downloaded ? "checkmark.circle.fill" : "arrow.down.circle.dotted")
                    .font(.body)
                    .foregroundStyle(downloaded ? .green : .secondary)
                    .frame(width: 20)

                // Model info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.body)
                            .fontWeight(isSelected ? .bold : .medium)
                            .foregroundStyle(.primary)

                        Text(model.quantization)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(.secondary)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    HStack(spacing: 12) {
                        // Disk size
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.doc")
                                .font(.caption2)
                            Text(model.diskSizeLabel)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)

                        // RAM size
                        HStack(spacing: 3) {
                            Image(systemName: "memorychip")
                                .font(.caption2)
                            Text(model.ramSizeLabel)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)

                        // Actual on-disk if downloaded
                        if let actualSize = model.downloadedSizeLabel {
                            HStack(spacing: 3) {
                                Image(systemName: "internaldrive")
                                    .font(.caption2)
                                Text(actualSize)
                                    .font(.caption)
                            }
                            .foregroundStyle(.green)
                        }
                    }

                    // Note
                    if let note = model.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .id("\(model.id)-\(refreshID)")
    }
}
