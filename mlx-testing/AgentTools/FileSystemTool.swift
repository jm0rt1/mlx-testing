import Foundation

// MARK: - File System Tool

/// Lets the LLM read files, list directories, write files, and check file info.
/// Scoped to the user's home directory for safety.
struct FileSystemTool: AgentTool {

    let name = "file_system"

    let toolDescription = """
        Read, write, and list files on the local file system. \
        Can read file contents, list directory contents, write text to files, \
        and get file metadata (size, dates). Paths are relative to the user's home directory.
        """

    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: .string,
            description: "The operation to perform",
            required: true,
            enumValues: ["read", "list", "write", "info", "search"]
        ),
        ToolParameter(
            name: "path",
            type: .string,
            description: "File or directory path (relative to home, or absolute)",
            required: true
        ),
        ToolParameter(
            name: "content",
            type: .string,
            description: "Content to write (required for 'write' action)",
            required: false
        ),
        ToolParameter(
            name: "pattern",
            type: .string,
            description: "Search pattern (for 'search' action, glob-style)",
            required: false
        ),
    ]

    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        guard let rawPath = arguments["path"]?.stringValue else {
            throw ToolError.missingRequiredParameter("path")
        }

        let path = resolvePath(rawPath)

        switch action {
        case "read":
            return try readFile(at: path)
        case "list":
            return try listDirectory(at: path)
        case "write":
            guard let content = arguments["content"]?.stringValue else {
                throw ToolError.missingRequiredParameter("content")
            }
            return try writeFile(at: path, content: content)
        case "info":
            return try fileInfo(at: path)
        case "search":
            let pattern = arguments["pattern"]?.stringValue ?? "*"
            return try searchFiles(at: path, pattern: pattern)
        default:
            throw ToolError.executionFailed("Unknown action: \(action). Use: read, list, write, info, search")
        }
    }

    // MARK: - Actions

    private func readFile(at path: String) throws -> ToolResult {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return ToolResult(toolName: name, success: false, output: "File not found: \(path)")
        }

        let content = try String(contentsOf: url, encoding: .utf8)

        // Truncate very large files
        let maxChars = 10_000
        let truncated = content.count > maxChars
        let output = truncated
            ? String(content.prefix(maxChars)) + "\n\n... [truncated, \(content.count) total characters]"
            : content

        return ToolResult(
            toolName: name,
            success: true,
            output: output,
            artifacts: [ToolArtifact(type: .filePath, label: "File", value: path)]
        )
    }

    private func listDirectory(at path: String) throws -> ToolResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return ToolResult(toolName: name, success: false, output: "Directory not found: \(path)")
        }

        let contents = try fm.contentsOfDirectory(atPath: path)
        var lines: [String] = []

        for item in contents.sorted() {
            var isDir: ObjCBool = false
            let fullPath = (path as NSString).appendingPathComponent(item)
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            if isDir.boolValue {
                lines.append("📁 \(item)/")
            } else {
                let size = (try? fm.attributesOfItem(atPath: fullPath)[.size] as? Int) ?? 0
                lines.append("📄 \(item) (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))")
            }
        }

        let output = lines.isEmpty ? "(empty directory)" : lines.joined(separator: "\n")
        return ToolResult(
            toolName: name,
            success: true,
            output: "Contents of \(path):\n\(output)"
        )
    }

    private func writeFile(at path: String, content: String) throws -> ToolResult {
        let url = URL(fileURLWithPath: path)

        // Ensure parent directory exists
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        try content.write(to: url, atomically: true, encoding: .utf8)

        return ToolResult(
            toolName: name,
            success: true,
            output: "Wrote \(content.count) characters to \(path)",
            artifacts: [ToolArtifact(type: .filePath, label: "Written file", value: path)]
        )
    }

    private func fileInfo(at path: String) throws -> ToolResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return ToolResult(toolName: name, success: false, output: "File not found: \(path)")
        }

        let attrs = try fm.attributesOfItem(atPath: path)
        let size = attrs[.size] as? Int ?? 0
        let created = attrs[.creationDate] as? Date
        let modified = attrs[.modificationDate] as? Date
        let type = attrs[.type] as? FileAttributeType

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        var lines = [
            "Path: \(path)",
            "Type: \(type == .typeDirectory ? "Directory" : "File")",
            "Size: \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))",
        ]
        if let created { lines.append("Created: \(df.string(from: created))") }
        if let modified { lines.append("Modified: \(df.string(from: modified))") }

        return ToolResult(toolName: name, success: true, output: lines.joined(separator: "\n"))
    }

    private func searchFiles(at path: String, pattern: String) throws -> ToolResult {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else {
            return ToolResult(toolName: name, success: false, output: "Cannot enumerate: \(path)")
        }

        var matches: [String] = []
        let maxResults = 50

        while let item = enumerator.nextObject() as? String {
            if matches.count >= maxResults { break }
            if item.localizedCaseInsensitiveContains(pattern.replacingOccurrences(of: "*", with: "")) {
                matches.append(item)
            }
        }

        let output = matches.isEmpty
            ? "No files matching '\(pattern)' in \(path)"
            : "Found \(matches.count) match(es):\n" + matches.map { "  \($0)" }.joined(separator: "\n")

        return ToolResult(toolName: name, success: true, output: output)
    }

    // MARK: - Path Resolution

    private func resolvePath(_ raw: String) -> String {
        if raw.hasPrefix("/") { return raw }
        if raw.hasPrefix("~") {
            return NSString(string: raw).expandingTildeInPath
        }
        // Relative to home
        return NSHomeDirectory() + "/" + raw
    }
}
