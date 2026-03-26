import SwiftUI

/// A toolbar button that opens a popover showing all available models
/// from the dynamic catalog with download status, sizes, and metadata.
struct ModelPickerView: View {
    @Binding var selectedModelID: String
    @ObservedObject var catalog: ModelCatalogService

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            let model = catalog.find(id: selectedModelID)
            Label(model?.displayName ?? "Select Model", systemImage: "cpu")
        }
        .help("Select model")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ModelPopoverContent(
                selectedModelID: $selectedModelID,
                showPopover: $showPopover,
                catalog: catalog
            )
        }
    }
}

// MARK: - Popover Content

private struct ModelPopoverContent: View {
    @Binding var selectedModelID: String
    @Binding var showPopover: Bool
    @ObservedObject var catalog: ModelCatalogService

    @State private var refreshID = UUID()
    @State private var searchText = ""
    @State private var modelToDelete: ModelInfo?
    @State private var sortOrder: SortOrder = .downloads
    @State private var showOnlyDownloaded = false
    @State private var showOnlyFitsRAM = false

    enum SortOrder: String, CaseIterable {
        case downloads = "Downloads"
        case size = "Size"
        case name = "Name"
        case family = "Family"
    }

    private var filteredModels: [ModelInfo] {
        var result = catalog.models

        // Text filter
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.displayName.lowercased().contains(q)
                || $0.family.lowercased().contains(q)
                || $0.parameterLabel.lowercased().contains(q)
                || $0.id.lowercased().contains(q)
                || $0.modelType.lowercased().contains(q)
            }
        }

        // Toggle filters
        if showOnlyDownloaded {
            result = result.filter(\.isDownloaded)
        }
        if showOnlyFitsRAM {
            result = result.filter { $0.fitsInRAM() }
        }

        // Sort
        switch sortOrder {
        case .downloads:
            result.sort { $0.downloads > $1.downloads }
        case .size:
            result.sort { $0.storageSizeBytes < $1.storageSizeBytes }
        case .name:
            result.sort { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        case .family:
            result.sort { $0.family.localizedCompare($1.family) == .orderedAscending }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            filterBar
            Divider()
            modelList
            Divider()
            storageFooter
        }
        .frame(width: 480, height: 560)
        .alert("Delete Model?", isPresented: showDeleteAlert) {
            Button("Cancel", role: .cancel) { modelToDelete = nil }
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    model.deleteFromDisk()
                    refreshID = UUID()
                }
                modelToDelete = nil
            }
        } message: {
            if let model = modelToDelete {
                Text("Remove \(model.displayName) from disk?\n\nThis frees \(model.downloadedSizeLabel ?? "space") and the model will need to be re-downloaded to use again.")
            }
        }
    }

    private var showDeleteAlert: Binding<Bool> {
        Binding(
            get: { modelToDelete != nil },
            set: { if !$0 { modelToDelete = nil } }
        )
    }

    // MARK: - Header with search + refresh

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search models…", text: $searchText)
                .textFieldStyle(.plain)
            Spacer()
            if catalog.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
            Button {
                Task { await catalog.refreshFromAPI() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh catalog from Hugging Face")
            .disabled(catalog.isLoading)
        }
        .padding(10)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Spacer()

            Toggle("Downloaded", isOn: $showOnlyDownloaded)
                .toggleStyle(.checkbox)
                .font(.caption)

            Toggle("Fits RAM", isOn: $showOnlyFitsRAM)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Model list

    private var modelList: some View {
        Group {
            if catalog.isLoading && catalog.models.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Fetching models from Hugging Face…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredModels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No models match your filters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredModels) { model in
                            ModelRow(
                                model: model,
                                isSelected: model.id == selectedModelID,
                                refreshID: refreshID,
                                onSelect: {
                                    selectedModelID = model.id
                                    showPopover = false
                                },
                                onDelete: {
                                    modelToDelete = model
                                }
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Footer

    private var storageFooter: some View {
        HStack(spacing: 12) {
            // Last refreshed
            if let last = catalog.lastRefreshed {
                Text("Updated \(last, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let error = catalog.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption2)
                    .help(error)
            }

            Spacer()

            Text("\(catalog.models.count) models")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            let dlCount = catalog.downloadedCount
            if dlCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive")
                        .font(.caption2)
                    Text("\(dlCount) cached · \(catalog.totalDownloadedSizeLabel)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Model Row

private struct ModelRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let refreshID: UUID
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                rowContent
            }
            .buttonStyle(.plain)

            if model.isDownloaded, !isSelected {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .help("Delete \(model.displayName) from disk")
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .padding(.horizontal, 4)
        .onHover { hovering in isHovering = hovering }
        .id("\(model.id)-\(refreshID)")
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            let downloaded = model.isDownloaded
            Image(systemName: downloaded ? "checkmark.circle.fill" : "arrow.down.circle.dotted")
                .font(.body)
                .foregroundStyle(downloaded ? .green : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                // Name row
                HStack(spacing: 6) {
                    Text(model.shortName)
                        .font(.body)
                        .fontWeight(isSelected ? .bold : .medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(model.quantizationLabel)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(.secondary)

                    if !model.parameterLabel.isEmpty {
                        Text(model.parameterLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                // Size + metadata row
                sizeRow

                // Author
                Text(model.author)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 10) {
            // Download / disk size
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.doc")
                    .font(.caption2)
                Text(model.storageSizeLabel)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            // Estimated RAM
            HStack(spacing: 3) {
                Image(systemName: "memorychip")
                    .font(.caption2)
                Text(model.estimatedRAMLabel)
                    .font(.caption)
            }
            .foregroundColor(model.fitsInRAM() ? .secondary : .orange)

            // Downloads count
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.to.line")
                    .font(.caption2)
                Text(model.downloadsLabel)
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)

            // Actual on-disk size if downloaded
            if let actualSize = model.downloadedSizeLabel {
                HStack(spacing: 3) {
                    Image(systemName: "internaldrive")
                        .font(.caption2)
                    Text(actualSize)
                        .font(.caption)
                }
                .foregroundStyle(.green)
            }

            // RAM warning
            if !model.fitsInRAM() {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("May not fit in 24 GB RAM")
            }
        }
    }
}
