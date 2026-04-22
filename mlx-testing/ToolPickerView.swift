import SwiftUI

/// A toolbar button that opens a popover for browsing and toggling individual tools.
struct ToolPickerView: View {
    @Binding var toolsEnabled: Bool
    @ObservedObject var registry: ToolRegistry

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Label(
                toolsEnabled ? "\(registry.enabledToolCount)/\(registry.tools.count)" : "Off",
                systemImage: toolsEnabled ? "hammer.fill" : "hammer"
            )
        }
        .help(toolsEnabled
              ? "\(registry.enabledToolCount) of \(registry.tools.count) tools enabled"
              : "Agent tools disabled")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ToolPopoverContent(
                toolsEnabled: $toolsEnabled,
                registry: registry
            )
        }
    }
}

// MARK: - Popover Content

private struct ToolPopoverContent: View {
    @Binding var toolsEnabled: Bool
    @ObservedObject var registry: ToolRegistry

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            toolList
            Divider()
            footerBar
        }
        .frame(width: 360, height: 400)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .foregroundStyle(.orange)
            Text("Agent Tools")
                .font(.headline)
            Spacer()
            Toggle("Enable All", isOn: $toolsEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(toolsEnabled ? "Disable all tools" : "Enable all tools")
        }
        .padding(10)
    }

    // MARK: - Tool List

    private var sortedTools: [any AgentTool] {
        registry.tools.values.sorted { $0.name < $1.name }
    }

    private var toolList: some View {
        Group {
            if registry.tools.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "hammer")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No tools registered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedTools, id: \.name) { tool in
                            ToolRow(
                                tool: tool,
                                isEnabled: registry.isToolEnabled(tool.name),
                                isMasterEnabled: toolsEnabled,
                                onToggle: { enabled in
                                    registry.setToolEnabled(tool.name, enabled: enabled)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            Text(toolsEnabled
                 ? "\(registry.enabledToolCount) of \(registry.tools.count) enabled"
                 : "All tools disabled")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            if toolsEnabled {
                Button("Enable All") {
                    for tool in registry.tools.values {
                        registry.setToolEnabled(tool.name, enabled: true)
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.accentColor)
                .disabled(registry.enabledToolCount == registry.tools.count)

                Button("Disable All") {
                    for tool in registry.tools.values {
                        registry.setToolEnabled(tool.name, enabled: false)
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.accentColor)
                .disabled(registry.enabledToolCount == 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Tool Row

private struct ToolRow: View {
    let tool: any AgentTool
    let isEnabled: Bool
    let isMasterEnabled: Bool
    let onToggle: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .disabled(!isMasterEnabled)

            Image(systemName: toolIcon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(isEnabled && isMasterEnabled ? .primary : .secondary)

                    riskBadge
                }

                Text(toolSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .padding(.horizontal, 4)
        .onHover { hovering in isHovering = hovering }
    }

    private var toolIcon: String {
        switch tool.name {
        case "file_system": return "doc.text"
        case "shell": return "terminal"
        case "clipboard": return "paperclip"
        case "open": return "arrow.up.forward.app"
        case "calendar": return "calendar"
        default: return "wrench"
        }
    }

    private var iconColor: Color {
        guard isEnabled && isMasterEnabled else { return .secondary }
        switch tool.riskLevel {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private var riskBadge: some View {
        Text(tool.riskLevel.rawValue)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(riskBadgeColor.opacity(0.15))
            )
            .foregroundStyle(riskBadgeColor)
    }

    private var riskBadgeColor: Color {
        switch tool.riskLevel {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private var toolSummary: String {
        // Use a short summary — first sentence of the description
        let desc = tool.toolDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let dotRange = desc.range(of: ".") {
            return String(desc[desc.startIndex...dotRange.lowerBound])
        }
        return desc
    }
}
