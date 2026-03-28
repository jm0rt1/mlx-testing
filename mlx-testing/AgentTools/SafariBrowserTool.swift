import AppKit
import Foundation

// MARK: - Safari Browser Tool

/// Controls Safari via AppleScript — get active tab, open URLs, read page text,
/// search the web, list tabs, get HTML source, and run JavaScript.
/// Safari is launched automatically via NSWorkspace if not running.
struct SafariBrowserTool: AgentTool {

    let name = "safari"

    let toolDescription = """
        Control Safari to browse the web. \
        Use search_web to open a URL and immediately read the page text in one step — this is the best action for answering questions from the internet. \
        Also supports: current_tab (get active tab info), open_url (just open without reading), \
        list_tabs, read_page (read current page text), get_source (raw HTML), run_js (execute JavaScript).
        """

    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: .string,
            description: "The operation to perform",
            required: true,
            enumValues: ["search_web", "current_tab", "open_url", "list_tabs", "read_page", "get_source", "run_js"]
        ),
        ToolParameter(
            name: "url",
            type: .string,
            description: "URL to open (required for open_url and search_web)",
            required: false
        ),
        ToolParameter(
            name: "javascript",
            type: .string,
            description: "JavaScript snippet to evaluate in the current tab (required for run_js)",
            required: false
        ),
    ]

    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    // MARK: - Execute

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }

        // Ensure Safari is running before any action
        await ensureSafariRunning()

        switch action {
        case "search_web":
            guard let url = arguments["url"]?.stringValue, !url.isEmpty else {
                throw ToolError.missingRequiredParameter("url")
            }
            return await searchWeb(url)
        case "current_tab":
            return currentTab()
        case "open_url":
            guard let url = arguments["url"]?.stringValue, !url.isEmpty else {
                throw ToolError.missingRequiredParameter("url")
            }
            return await openURL(url)
        case "list_tabs":
            return listTabs()
        case "read_page":
            return readPage()
        case "get_source":
            return getSource()
        case "run_js":
            guard let js = arguments["javascript"]?.stringValue, !js.isEmpty else {
                throw ToolError.missingRequiredParameter("javascript")
            }
            return runJavaScript(js)
        default:
            throw ToolError.executionFailed(
                "Unknown action: \(action). Use: search_web, current_tab, open_url, list_tabs, read_page, get_source, run_js"
            )
        }
    }

    // MARK: - Safari Lifecycle

    /// Launch Safari if not running, using /usr/bin/open which is the most
    /// reliable way to launch apps on macOS (works from sandbox, any thread).
    private func ensureSafariRunning() async {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Safari"
        }
        guard !running else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Safari"]
        try? proc.run()
        proc.waitUntilExit()
        // Wait for Safari to fully start and register its AppleScript interface
        try? await Task.sleep(nanoseconds: 3_000_000_000)
    }

    // MARK: - Actions

    /// Opens a URL in Safari, waits for it to load, then reads the page text.
    /// This is the all-in-one action for web lookups — no second tool call needed.
    private func searchWeb(_ url: String) async -> ToolResult {
        // Step 1: Open the URL
        let openResult = await openURL(url)
        guard openResult.success else { return openResult }

        // Step 2: Wait a bit more for content to render
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Step 3: Read the page text
        let pageResult = readPage()
        if pageResult.success && pageResult.output.count > 100 {
            return pageResult
        }

        // If the first read was too short, wait a bit more and retry
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        return readPage()
    }

    private func currentTab() -> ToolResult {
        runAppleScript("""
            tell application "Safari"
                if (count of windows) = 0 then return "No Safari windows open."
                set t to current tab of front window
                return "URL: " & URL of t & linefeed & "Title: " & name of t
            end tell
            """)
    }

    private func openURL(_ url: String) async -> ToolResult {
        let sanitized = url.replacingOccurrences(of: "\"", with: "")

        // Use /usr/bin/open to open URL in Safari — works from sandbox, any thread
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Safari", sanitized]
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return ToolResult(toolName: name, success: false, output: "Failed to open URL: \(error.localizedDescription)")
        }

        // Brief wait for navigation to begin
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // Check what loaded
        let check = runAppleScript("""
            tell application "Safari"
                if (count of windows) = 0 then return "Page loading..."
                set t to current tab of front window
                return "URL: " & URL of t & linefeed & "Title: " & name of t
            end tell
            """)

        return ToolResult(
            toolName: name,
            success: true,
            output: "Opened in Safari.\n\(check.output)"
        )
    }

    private func listTabs() -> ToolResult {
        runAppleScript("""
            tell application "Safari"
                if (count of windows) = 0 then return "No Safari windows open."
                set output to ""
                set winNum to 0
                repeat with w in windows
                    set winNum to winNum + 1
                    set tabNum to 0
                    repeat with t in tabs of w
                        set tabNum to tabNum + 1
                        set output to output & "Window " & winNum & ", Tab " & tabNum & ": " & (URL of t) & " | " & (name of t) & linefeed
                    end repeat
                end repeat
                return output
            end tell
            """, maxChars: 5_000)
    }

    /// Extract readable text from the current page using JavaScript.
    /// Strips scripts, styles, nav, ads — returns clean text the LLM can process.
    private func readPage() -> ToolResult {
        // Build JS as a single-line string, use only single quotes inside
        // so it embeds cleanly in AppleScript's "..." string
        let js = "(function(){var c=document.body.cloneNode(true);var r=c.querySelectorAll('script,style,nav,header,footer,iframe,noscript,svg');for(var i=0;i<r.length;i++)r[i].remove();var t=c.innerText||'';return t.substring(0,8000)})()"

        // AppleScript does not use backslash escapes, so we only need to
        // escape actual double-quote characters (there are none in this JS)
        let escapedJS = js.replacingOccurrences(of: "\"", with: "\\\"")

        let script = "tell application \"Safari\"\n"
            + "if (count of windows) = 0 then return \"No Safari windows open.\"\n"
            + "set pageURL to URL of current tab of front window\n"
            + "set pageTitle to name of current tab of front window\n"
            + "set pageText to do JavaScript \"\(escapedJS)\" in current tab of front window\n"
            + "return \"URL: \" & pageURL & linefeed & \"Title: \" & pageTitle & linefeed & linefeed & pageText\n"
            + "end tell"

        return runAppleScript(script, maxChars: 5_000)
    }

    private func getSource() -> ToolResult {
        runAppleScript("""
            tell application "Safari"
                if (count of documents) = 0 then return "No Safari documents open."
                return source of document 1
            end tell
            """, maxChars: 10_000)
    }

    private func runJavaScript(_ js: String) -> ToolResult {
        let escaped = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return runAppleScript("""
            tell application "Safari"
                if (count of windows) = 0 then return "No Safari windows open."
                do JavaScript "\(escaped)" in current tab of front window
            end tell
            """)
    }

    // MARK: - AppleScript Runner

    private func runAppleScript(_ script: String, maxChars: Int = 3_000) -> ToolResult {
        print("[Safari] Running AppleScript (\(script.count) chars):")
        print("[Safari] \(script.prefix(500))")
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return ToolResult(toolName: name, success: false, output: "Failed to create AppleScript.")
        }

        let descriptor = appleScript.executeAndReturnError(&error)

        if let err = error {
            let message = err[NSAppleScript.errorMessage] as? String ?? "\(err)"
            return ToolResult(toolName: name, success: false, output: "AppleScript error: \(message)")
        }

        var text = descriptor.stringValue ?? "(no output)"
        if text.count > maxChars {
            text = String(text.prefix(maxChars)) + "\n... [truncated, \(text.count) total chars]"
        }
        return ToolResult(toolName: name, success: true, output: text)
    }
}
