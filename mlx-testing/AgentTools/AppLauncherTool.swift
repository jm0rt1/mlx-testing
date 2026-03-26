import AppKit
import Foundation

// MARK: - App Launcher Tool

/// Lets the LLM open applications, URLs, and files using macOS services.
struct AppLauncherTool: AgentTool {

    let name = "open"

    let toolDescription = """
        Open applications, URLs, or files on macOS. \
        Can launch apps by name, open URLs in the default browser, \
        open files with their default application, or list running applications.
        """

    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: .string,
            description: "The operation to perform",
            required: true,
            enumValues: ["app", "url", "file", "list_running"]
        ),
        ToolParameter(
            name: "target",
            type: .string,
            description: "App name, URL, or file path to open (not needed for list_running)",
            required: false
        ),
    ]

    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }

        switch action {
        case "app":
            guard let target = arguments["target"]?.stringValue else {
                throw ToolError.missingRequiredParameter("target")
            }
            return await openApp(target)
        case "url":
            guard let target = arguments["target"]?.stringValue else {
                throw ToolError.missingRequiredParameter("target")
            }
            return await openURL(target)
        case "file":
            guard let target = arguments["target"]?.stringValue else {
                throw ToolError.missingRequiredParameter("target")
            }
            return await openFile(target)
        case "list_running":
            return listRunningApps()
        default:
            throw ToolError.executionFailed("Unknown action: \(action). Use: app, url, file, list_running")
        }
    }

    // MARK: - Actions

    private func openApp(_ appName: String) async -> ToolResult {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        // Try to find the app URL
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName)
            ?? findAppByName(appName) else {
            return ToolResult(
                toolName: name,
                success: false,
                output: "Could not find application: \(appName). Try using the exact app name (e.g. 'Safari', 'Terminal')."
            )
        }

        do {
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return ToolResult(
                toolName: name,
                success: true,
                output: "Opened application: \(appURL.lastPathComponent)"
            )
        } catch {
            return ToolResult(
                toolName: name,
                success: false,
                output: "Failed to open \(appName): \(error.localizedDescription)"
            )
        }
    }

    private func openURL(_ urlString: String) async -> ToolResult {
        guard let url = URL(string: urlString), url.scheme != nil else {
            return ToolResult(
                toolName: name,
                success: false,
                output: "Invalid URL: \(urlString)"
            )
        }

        let opened = NSWorkspace.shared.open(url)
        return ToolResult(
            toolName: name,
            success: opened,
            output: opened ? "Opened URL: \(urlString)" : "Failed to open URL: \(urlString)"
        )
    }

    private func openFile(_ path: String) async -> ToolResult {
        let resolvedPath: String
        if path.hasPrefix("~") {
            resolvedPath = NSString(string: path).expandingTildeInPath
        } else if path.hasPrefix("/") {
            resolvedPath = path
        } else {
            resolvedPath = NSHomeDirectory() + "/" + path
        }

        let url = URL(fileURLWithPath: resolvedPath)
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return ToolResult(
                toolName: name,
                success: false,
                output: "File not found: \(resolvedPath)"
            )
        }

        let opened = NSWorkspace.shared.open(url)
        return ToolResult(
            toolName: name,
            success: opened,
            output: opened ? "Opened file: \(resolvedPath)" : "Failed to open file: \(resolvedPath)"
        )
    }

    private func listRunningApps() -> ToolResult {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> String? in
                guard let name = app.localizedName else { return nil }
                let bundleID = app.bundleIdentifier ?? "unknown"
                return "• \(name) (\(bundleID))"
            }
            .sorted()

        let output = apps.isEmpty
            ? "No running applications found."
            : "Running applications (\(apps.count)):\n" + apps.joined(separator: "\n")

        return ToolResult(toolName: name, success: true, output: output)
    }

    // MARK: - Helpers

    private func findAppByName(_ appName: String) -> URL? {
        let searchPaths = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]

        let fm = FileManager.default
        for dir in searchPaths {
            let appPath = "\(dir)/\(appName).app"
            if fm.fileExists(atPath: appPath) {
                return URL(fileURLWithPath: appPath)
            }
        }

        // Fuzzy match: try case-insensitive search
        for dir in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents {
                if item.lowercased().hasPrefix(appName.lowercased()) && item.hasSuffix(".app") {
                    return URL(fileURLWithPath: "\(dir)/\(item)")
                }
            }
        }

        return nil
    }
}
