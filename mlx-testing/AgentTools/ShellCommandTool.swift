import Foundation

// MARK: - Shell Command Tool

/// Lets the LLM execute shell commands on the local machine.
/// Commands run via /bin/bash with a timeout and output capture.
struct ShellCommandTool: AgentTool {

    let name = "shell"

    let toolDescription = """
        Execute a shell command on the local machine via /bin/bash. \
        Returns stdout and stderr. Use for system queries, package management, \
        git operations, file processing, etc. Commands have a 30-second timeout.
        """

    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "command",
            type: .string,
            description: "The shell command to execute",
            required: true
        ),
        ToolParameter(
            name: "working_directory",
            type: .string,
            description: "Working directory for the command (default: home directory)",
            required: false
        ),
        ToolParameter(
            name: "timeout",
            type: .integer,
            description: "Timeout in seconds (default: 30, max: 120)",
            required: false,
            defaultValue: "30"
        ),
    ]

    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .high

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let command = arguments["command"]?.stringValue else {
            throw ToolError.missingRequiredParameter("command")
        }

        let workDir: String
        if let wd = arguments["working_directory"]?.stringValue {
            workDir = wd.hasPrefix("~") ? NSString(string: wd).expandingTildeInPath : wd
        } else {
            workDir = NSHomeDirectory()
        }

        let timeoutSecs: Int
        if case .integer(let t) = arguments["timeout"] {
            timeoutSecs = min(t, 120)
        } else {
            timeoutSecs = 30
        }

        return await runCommand(command, workingDirectory: workDir, timeout: timeoutSecs)
    }

    // MARK: - Execution

    private func runCommand(_ command: String, workingDirectory: String, timeout: Int) async -> ToolResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Environment: inherit current + ensure PATH includes common locations
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin"
        process.environment = env

        do {
            try process.run()
        } catch {
            return ToolResult(
                toolName: name,
                success: false,
                output: "Failed to start process: \(error.localizedDescription)"
            )
        }

        // Timeout handling
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let exitCode = process.terminationStatus

        // Truncate very long output
        let maxChars = 8_000
        let truncateNote = "\n\n... [output truncated]"

        var output = "$ \(command)\n"
        output += "Exit code: \(exitCode)\n"

        if !stdout.isEmpty {
            output += "\n[stdout]\n"
            output += stdout.count > maxChars
                ? String(stdout.prefix(maxChars)) + truncateNote
                : stdout
        }
        if !stderr.isEmpty {
            output += "\n[stderr]\n"
            output += stderr.count > maxChars
                ? String(stderr.prefix(maxChars)) + truncateNote
                : stderr
        }

        return ToolResult(
            toolName: name,
            success: exitCode == 0,
            output: output
        )
    }
}
