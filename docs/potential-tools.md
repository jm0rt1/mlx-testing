# Potential Agent Tools — Brainstorming Catalogue

This document is a wide-ranging catalogue of tool ideas that could extend the MLX Copilot agent system. Every tool described here would conform to the `AgentTool` protocol, be registered in `ToolRegistry`, and become available to the LLM via the agentic loop.

The list is organised by category. For each tool, a short description and a sample set of key capabilities is provided. Risk levels follow the existing convention: **low** (read-only / benign), **medium** (writes data / launches apps), **high** (executes code / modifies system state).

---

## 1. macOS System & Hardware

### `SystemInfoTool` *(low)*
Query live hardware and OS telemetry.
- CPU model, core count, usage per core
- RAM installed, available, pressure (normal / warning / critical)
- GPU / ANE utilisation via IOKit
- Battery charge, cycle count, charging state
- Disk free / used space per volume
- macOS version, build string, kernel version

### `ProcessManagerTool` *(medium)*
Inspect and control running processes.
- List all processes with PID, CPU %, memory %, name
- Kill a process by PID or name (with approval)
- Find processes listening on a specific port
- Report open file descriptors for a process

### `DisplayTool` *(medium)*
Manage screen configuration.
- List connected displays with resolution and refresh rate
- Set screen brightness (0–100 %)
- Enable / disable Night Shift or True Tone
- Take a screenshot of a specific window or region (returns a file path)
- Mirror or extend displays

### `AudioTool` *(medium)*
Control system audio and media playback.
- Get / set system output volume and mute state
- List input and output audio devices
- Switch the default audio device
- Control Music.app or Spotify (play, pause, skip, current track)
- Transcribe an audio file via AVFoundation

### `BluetoothTool` *(medium)*
Manage Bluetooth devices.
- List paired devices with connection state
- Connect / disconnect a device by name or address
- Report signal strength (RSSI)

### `WiFiTool` *(low)*
Inspect wireless network status.
- Current SSID, signal strength, security type
- List available networks
- Get external IP address and DNS servers
- Ping a host and report round-trip time

### `NotificationTool` *(low)*
Post and schedule user-visible notifications.
- Deliver an immediate `UNUserNotification` with title, body, and optional action buttons
- Schedule a time-based reminder notification
- List pending and delivered notifications

### `KeychainTool` *(high)*
Securely store and retrieve secrets.
- Save a password or API key under a service label
- Retrieve a stored secret by service and account
- Delete a keychain item
- List service names for which items exist (no values exposed)

### `SpotlightTool` *(low)*
Search the local file system using `MDQuery`.
- Full-text and metadata search across all indexed files
- Filter by `kMDItemKind`, file extension, date range, author
- Return file paths, names, and key metadata attributes

### `AccessibilityInspectorTool` *(low)*
Inspect the accessibility tree of any running application.
- List UI elements (buttons, text fields, windows) with their AX roles and labels
- Read the text content of any focused element
- Useful for building macOS automation scripts

---

## 2. Developer Productivity

### `GitTool` *(medium)*
Run common Git operations against any local repository.
- `git status` — summarise staged / unstaged changes
- `git diff` — show a diff for a path or commit range
- `git log` — list recent commits with author and message
- `git blame` — show who wrote each line of a file
- `git commit` / `git push` (require explicit approval)
- `git stash`, `git branch`, `git checkout`

### `XcodeTool` *(high)*
Drive Xcode builds and tests via `xcodebuild`.
- Build a scheme in a `.xcodeproj` or `.xcworkspace`
- Run the test suite and return pass / fail counts with failure messages
- Clean the derived data folder
- Archive and export an IPA

### `SwiftFormatTool` *(medium)*
Format Swift source files.
- Run `swift-format` or `swiftlint --fix` on a file or directory
- Return a unified diff of the formatting changes
- Report rule violations without applying them (lint-only mode)

### `DependencyAuditTool` *(low)*
Analyse Swift Package dependencies.
- Resolve and list all direct and transitive packages
- Check for packages with known security advisories
- Report outdated packages compared to the latest registry versions

### `DockerTool` *(high)*
Manage local Docker / OrbStack containers.
- List running and stopped containers with status
- Start, stop, and remove containers by name or ID
- Pull an image and report its size
- Stream the last N lines of container logs
- Execute a command inside a running container

### `DatabaseTool` *(medium)*
Query local databases.
- Execute read-only SQL against any SQLite file and return results as JSON
- List tables, views, and indexes in a SQLite database
- Query Core Data persistent stores by entity name (via direct SQLite access)
- Export a table to CSV

### `RegexTool` *(low)*
Apply regular expressions to text or files.
- Test whether a pattern matches a string, with match groups
- Search all lines in a file or directory that match a pattern
- Replace occurrences in text (returns modified string, does not write to disk)
- Validate regex syntax and explain capture groups in plain English

### `DiffTool` *(low)*
Compute and display diffs.
- Unified diff between two strings or two file paths
- Word-level diff for prose changes
- Directory diff: which files were added, removed, or modified

### `REPLTool` *(high)*
Evaluate code snippets in a sandboxed subprocess.
- Swift snippet evaluation using `swift -e`
- Python 3 snippet evaluation
- JavaScript via JavaScriptCore
- Returns stdout, stderr, and exit code

### `HTTPClientTool` *(medium)*
Make HTTP / REST API calls.
- `GET`, `POST`, `PUT`, `PATCH`, `DELETE` with configurable headers and body
- Follow redirects, report status codes
- Parse JSON response and return as formatted string
- Set a configurable timeout (default 10 s)

### `WebScraperTool` *(medium)*
Fetch and parse web page content.
- Download a URL and return readable plain text (HTML stripped)
- Extract all links from a page
- Follow a pagination link up to N pages
- Return `<meta>` description and title without fetching the full page

---

## 3. Files & Documents

### `PDFTool` *(medium)*
Work with PDF files using PDFKit.
- Extract all text from a PDF file
- Extract text from a specific page range
- Merge multiple PDFs into one
- Split a PDF into individual pages
- Insert or rotate pages

### `MarkdownTool` *(low)*
Manipulate and render Markdown documents.
- Parse a Markdown file and return the document structure (headings, links, images)
- Convert Markdown to HTML
- Extract all headings as a table of contents
- Count words and reading time

### `SpreadsheetTool` *(medium)*
Read and write tabular data.
- Parse a CSV file into rows and columns
- Filter, sort, or aggregate rows (sum, average, min, max)
- Write a modified dataset back to CSV
- Read an `.xlsx` file's sheet names and cell ranges (via a bundled library)

### `ArchiveTool` *(medium)*
Create and extract archives.
- Compress a file or directory into a `.zip` using `Archive` (Apple's `AppleArchive` or `ZIPFoundation`)
- Extract a `.zip` or `.tar.gz` to a target directory
- List archive contents without extracting
- Compress large log files with gzip

### `ImageProcessingTool` *(medium)*
Resize, convert, and inspect images using Core Image.
- Get dimensions, colour space, and file size for an image file
- Resize an image to a max width / height
- Convert between JPEG, PNG, HEIC, and WEBP formats
- Apply a filter (greyscale, blur, sharpen, auto-enhance)
- Strip EXIF metadata for privacy

### `QRCodeTool` *(low)*
Generate and decode QR codes.
- Generate a QR code PNG from any string
- Decode a QR code from an image file or the clipboard
- Generate barcodes in Code 128 or PDF417 format

### `FontTool` *(low)*
Inspect installed fonts.
- List all installed font family names
- Return available styles (weights, widths) for a family
- Locate the file path of a specific font on disk

---

## 4. Productivity & Personal Data

### `CalendarTool` *(medium)*
Read and write calendar events via EventKit.
- List events in a date range across all or specific calendars
- Create a new event with title, location, start/end time, and notes
- Update or delete an existing event by event identifier
- Search events by keyword
- List upcoming reminders with due dates

### `RemindersTool` *(medium)*
Manage reminders via EventKit.
- List incomplete reminders across all or specific lists
- Create a new reminder with optional due date and priority
- Mark a reminder as complete
- Search reminders by keyword

### `ContactsTool` *(low)*
Search the user's contacts via CNContactStore.
- Find contacts by name, email, or phone number
- Return name, email addresses, phone numbers, and company
- List all contacts in a specific group

### `MailTool` *(medium)*
Interact with Mail.app via AppleScript.
- Count unread messages in a mailbox
- List the subject, sender, and date of recent unread messages
- Search messages by keyword
- Compose a draft (does not send without approval)
- Reply to a message by ID

### `SafariBrowserTool` *(medium)*
Control Safari via AppleScript.
- Get the URL and title of the active tab
- Open a new tab or window with a given URL
- Get the source HTML of the current page
- Execute a JavaScript snippet in the active tab
- List all open tabs with URLs and titles

### `NotesTool` *(medium)*
Read and write Apple Notes via AppleScript.
- List note titles and modification dates
- Read the full content of a note by title
- Create a new note with a title and body
- Append text to an existing note
- Search notes by keyword

### `PhotosTool` *(medium)*
Browse and export from the Photos library via PhotoKit.
- List albums and smart albums
- Search photos by date range, keyword, or place name
- Export a photo to a temporary file path
- Get metadata (GPS, camera model, date taken) for a photo

### `BookmarksTool` *(low)*
Manage browser bookmarks.
- List Safari bookmarks with title and URL
- Find bookmarks matching a keyword
- Add a new bookmark to a specified folder

---

## 5. AI & Multimodal

### `OCRTool` *(low)*
Extract text from images using the Vision framework.
- Run `VNRecognizeTextRequest` on any image file or path
- Return per-line recognised text with confidence scores
- Support English and other languages recognised by Vision
- Useful for reading screenshots, scanned documents, or photos of text

### `SpeechToTextTool` *(medium)*
Transcribe audio using a local Whisper model or Apple's Speech framework.
- Transcribe an audio file (`.m4a`, `.wav`, `.mp3`) to text
- Support multiple languages with automatic detection
- Return timestamps for each segment
- Record from the microphone for a specified duration and transcribe

### `TextToSpeechTool` *(low)*
Synthesise speech using `AVSpeechSynthesizer`.
- Convert a text string to speech using a chosen system voice
- Save synthesised audio to a `.caf` or `.m4a` file
- List available system voices with their language codes

### `ImageCaptioningTool` *(low)*
Describe the contents of an image using a local VLM.
- Pass an image file to the loaded vision-language model
- Return a natural-language caption
- Optionally answer a specific question about the image

### `EmbeddingTool` *(low)*
Compute semantic text embeddings using a local `MLXEmbedders` model.
- Embed a single string, returning a JSON float array
- Compute cosine similarity between two strings
- Find the most similar string in a list given a query

### `TranslationTool` *(low)*
Translate text using Apple's Translation framework (macOS 15+) or a local model.
- Translate a string from a source language to a target language
- Auto-detect the source language
- List supported language pairs

### `SentimentTool` *(low)*
Analyse the sentiment and tone of text.
- Return a sentiment score (positive / neutral / negative) with confidence
- Identify key emotional topics in a paragraph
- Useful for summarising customer feedback or journal entries

---

## 6. Web & External Services

### `WebSearchTool` *(medium)*
Search the internet and return results.
- Query a search engine (DuckDuckGo, Brave Search, or SearXNG) via their public JSON API
- Return titles, snippets, and URLs for the top N results
- Optionally fetch and return the full text of the top result

### `WikipediaTool` *(low)*
Look up information on Wikipedia.
- Search for articles by keyword
- Return the introductory summary of an article
- Return a specific section of an article by heading name

### `WeatherTool` *(low)*
Fetch current weather and forecasts.
- Get current conditions for a city name or coordinates via a public API (e.g. open-meteo.com)
- Return temperature, humidity, wind speed, and weather code
- 5-day forecast with daily high/low

### `RSSReaderTool` *(low)*
Parse RSS and Atom feeds.
- Fetch a feed URL and return the latest N items with title, date, and link
- Search across multiple saved feed URLs by keyword
- Detect feed format (RSS 2.0, Atom, JSON Feed)

### `GitHubTool` *(medium)*
Interact with GitHub's API.
- Search repositories by keyword
- List open issues or pull requests for a repo
- Read the content of a file in a repo by path and ref
- Post a comment on an issue or PR (requires a `GITHUB_TOKEN` stored in Keychain)
- Get the status of CI runs for a commit

### `SlackTool` *(medium)*
Post messages to Slack.
- Send a message to a channel via an Incoming Webhook URL stored in Keychain
- Format the message with Slack's Block Kit (sections, code blocks, links)
- Mention users or channels

### `JiraTool` *(medium)*
Query and update Jira issues.
- Search issues using JQL
- Get details of a specific issue (summary, description, status, assignee)
- Transition an issue to a new status
- Add a comment to an issue

---

## 7. Security & Privacy

### `PermissionsAuditTool` *(low)*
Audit macOS privacy permissions.
- List all apps that have been granted access to Camera, Microphone, Location, Contacts, Calendar, Reminders, Photos, Accessibility, and Full Disk Access
- Flag apps with unusually broad permissions
- Check whether a specific app has a specific permission

### `NetworkScannerTool` *(medium)*
Inspect the local network.
- List devices on the LAN with their IP and MAC addresses (via ARP)
- Perform a port scan on a host for common service ports
- Check whether a remote host / port is reachable

### `CertificateInspectorTool` *(low)*
Inspect TLS certificates.
- Fetch and display the certificate chain for a domain
- Report expiration dates, issuer, and subject
- Warn if a certificate expires within 30 days

### `EncryptionTool` *(high)*
Encrypt and decrypt data.
- Encrypt a file or string with AES-256-GCM using a passphrase
- Decrypt a previously encrypted file
- Compute SHA-256, SHA-512, or BLAKE3 hashes of a file or string
- Generate a cryptographically secure random passphrase

### `VaultTool` *(high)*
Manage a local encrypted note / secret vault.
- Store arbitrary key-value secrets in an AES-encrypted JSON file
- Retrieve secrets by key (requires approval)
- List key names without revealing values
- Rotate the vault encryption key

---

## 8. Automation & Scripting

### `AppleScriptTool` *(high)*
Execute AppleScript snippets.
- Run an arbitrary AppleScript and return its result
- Pre-built actions: front app name, front window title, frontmost document path
- Useful for automating any scriptable macOS application

### `ShortcutsTriggerTool` *(medium)*
Run macOS Shortcuts.
- List available Shortcuts by name
- Run a named Shortcut with optional input text
- Return the Shortcut's output as a string

### `CronSchedulerTool` *(medium)*
Schedule recurring tasks.
- Register a shell command or tool call to run on a cron-like schedule
- List scheduled tasks with their next run time
- Remove a scheduled task by ID
- Useful for automated log rotation, backups, or reminders

### `WebhookTool` *(medium)*
Send data to external services via HTTP webhooks.
- POST JSON payloads to a configured webhook URL
- Support custom headers (e.g. Authorization, Content-Type)
- Retry on failure with exponential back-off

### `TextExpansionTool` *(medium)*
Manage and trigger text expansion snippets.
- List saved abbreviation → expansion mappings
- Add or remove an abbreviation
- Expand a given abbreviation string to its full text

---

## 9. Knowledge & Mathematics

### `MathTool` *(low)*
Evaluate mathematical expressions.
- Compute arithmetic, algebraic, and trigonometric expressions using `NSExpression` or a bundled parser
- Convert between number bases (binary, octal, hex, decimal)
- Format results with specified precision

### `UnitConverterTool` *(low)*
Convert between units of measurement.
- Length, weight, volume, temperature, speed, data size, pressure, energy
- Uses `Measurement` + `UnitLength` etc. from the Foundation framework
- Return value with target unit symbol

### `CurrencyConverterTool` *(low)*
Convert between currencies.
- Fetch the latest exchange rates from a public API (e.g. exchangerate.host)
- Convert a value from one currency code to another
- List supported currency codes

### `TimezoneConverterTool` *(low)*
Work with dates and time zones.
- Convert a date and time from one time zone to another
- List all IANA time zone identifiers
- Calculate the current UTC offset for a time zone

### `CountdownTimerTool` *(low)*
Set and check countdown timers.
- Create a named countdown timer with a target date/time
- Report how much time remains on an active timer
- Notify the user (via `NotificationTool`) when the timer expires

### `PasswordGeneratorTool` *(low)*
Generate strong random credentials.
- Generate a password of configurable length, character sets, and entropy
- Generate a passphrase from a wordlist
- Estimate the crack time of a given password

---

## 10. Creative & Media

### `MermaidTool` *(low)*
Generate diagrams from Mermaid or PlantUML syntax.
- Render a Mermaid diagram definition to an SVG or PNG via a bundled renderer
- Suggest a diagram type (flowchart, sequence, ER, Gantt) given a description
- Validate diagram syntax and report errors

### `ColorTool` *(low)*
Work with colours and palettes.
- Parse a colour from hex, RGB, HSL, or CSS name
- Extract a dominant colour palette from an image file
- Convert between colour spaces (sRGB, P3, Lab)
- Generate a harmonious palette (complementary, triadic, analogous)

### `TextStylingTool` *(low)*
Apply typographic transformations to text.
- Convert to title case, sentence case, UPPER, lower, camelCase, snake_case
- Count words, sentences, paragraphs, and unique words
- Generate a Lorem Ipsum passage of N words or paragraphs

### `TemplateEngineTool` *(low)*
Render Mustache / Handlebars-style templates.
- Fill a template string with a JSON context object
- List variable placeholders in a template
- Useful for generating repetitive code, emails, or reports

### `SVGGeneratorTool` *(low)*
Create simple SVG graphics programmatically.
- Generate basic shapes (rect, circle, line, path) from parameters
- Combine shapes into a simple icon or badge
- Return the SVG source string

---

## 11. Collaboration & Communication

### `ZoomTool` *(medium)*
Interact with Zoom meetings.
- Start a meeting or join a meeting via its URL
- Return the join link for an upcoming scheduled meeting
- Mute / unmute the local microphone (via Zoom's URI scheme)

### `CalendarMeetingTool` *(medium)*
Schedule and summarise meetings.
- Find a free time slot for N attendees within a date range (requires access to calendars of invitees via shared calendar)
- Create a meeting invite with a Zoom / Teams / FaceTime link embedded
- Generate a meeting agenda from a bullet list of discussion topics

### `ContactEnricherTool` *(low)*
Look up public information about a person or organisation.
- Search LinkedIn-style data via a public API for company and job title
- Identify the domain of an email address and return its MX / SPF records
- Return social profile links from a name and company (privacy-respecting public lookup only)

---

## 12. Data Science & Analysis

### `DataAnalysisTool` *(low)*
Perform basic statistical analysis on structured data.
- Load a CSV and compute summary statistics (mean, median, std, quartiles) for each column
- Identify missing values and outliers
- Return a correlation matrix for numeric columns

### `ChartGeneratorTool` *(low)*
Create data visualisations.
- Generate a bar, line, scatter, or pie chart from CSV data using Swift Charts
- Export to PNG or SVG
- Annotate with title, axis labels, and a legend

### `LogParserTool` *(low)*
Parse and search log files.
- Tail the last N lines of a log file
- Filter log lines by severity, timestamp range, or keyword
- Extract unique IP addresses, error codes, or user agents from access logs
- Summarise error frequency over time

### `JSONTransformTool` *(low)*
Query and reshape JSON data.
- Apply a JSONPath or `jq`-style filter to a JSON string or file
- Merge two JSON objects or arrays
- Validate JSON against a JSON Schema
- Pretty-print or minify JSON

---

## 13. Location & Maps

### `LocationTool` *(low)*
Access the device's current location via CoreLocation (requires permission).
- Return latitude, longitude, altitude, and accuracy
- Reverse-geocode coordinates to a human-readable address
- Calculate the distance between two coordinates (Haversine formula)

### `MapsTool` *(low)*
Search and navigate with Maps.
- Search for a place by name and return its coordinates and address
- Get driving, walking, or transit directions between two addresses
- Open a location in the Maps app

---

## 14. Experimental & Forward-Looking

### `MemoryGraphTool` *(low)*
Build and query a persistent knowledge graph derived from conversations.
- Automatically extract entities (people, places, projects, dates) from messages
- Store relationships in a local graph database (e.g. a SQLite-backed adjacency list)
- Answer questions like "what projects is Alice involved in?" by traversing the graph

### `ProceduralTaskPlannerTool` *(low)*
Break a high-level goal into a step-by-step execution plan.
- Ask the LLM itself (via a secondary inference call) to decompose a task
- Return a numbered checklist of sub-tasks
- Track which steps have been completed in the current agentic loop

### `AgentSpawnTool` *(high)*
Spawn a subordinate agentic loop to handle a parallel sub-task.
- Create a child `ChatViewModel`-like context with a focused system prompt
- Execute a complete multi-step agent run and return the final result
- Useful for "write a unit test for this function while the main loop continues"

### `SelfReflectionTool` *(low)*
Let the model critique its own previous output.
- Pass the last N assistant messages to a review prompt
- Return a structured critique: correctness, clarity, completeness
- Optionally trigger a revision of the most recent message

### `ScreenAutomationTool` *(high)*
Automate the macOS GUI by interpreting screenshots.
- Capture the screen, pass it to a VLM, and return a structured description of UI elements
- Click on an element described by natural language (using `CGEvent` mouse simulation)
- Type text into the focused field
- Enables browser automation, form filling, and visual QA tasks without Accessibility APIs

### `VoiceMemoTool` *(medium)*
Record and transcribe voice notes.
- Start and stop microphone recording to a temporary file
- Transcribe using the local Whisper-based speech model
- Save the transcript as an Apple Note or text file

### `DreamJournalTool` *(medium)*
A specialised memory and journalling tool.
- Save a timestamped entry to a private encrypted journal file
- Search past entries by keyword or date
- Generate a weekly summary of recurring themes using the LLM
- Designed to model how the app could support deeply personal, offline workflows

---

## Implementation Notes

When implementing any tool from this list, follow the conventions described in the *Agent Tool System* section of the [project README](../README.md):

1. Create `mlx-testing/AgentTools/YourTool.swift`
2. Conform to `AgentTool` with appropriate `name`, `toolDescription`, `parameters`, `requiresApproval`, and `riskLevel`
3. Implement `execute(arguments:)` — truncate large outputs to a `maxChars` constant
4. Register in `ToolRegistry.registerDefaults()`
5. Update `mlx_testing.entitlements` if new sandbox permissions are needed
6. Update the README project structure table and this document's status column

| Category | Tools listed | Status |
|---|---|---|
| macOS System & Hardware | 9 | Potential |
| Developer Productivity | 10 | Potential |
| Files & Documents | 7 | Potential |
| Productivity & Personal Data | 7 | Potential |
| AI & Multimodal | 7 | Potential |
| Web & External Services | 7 | Potential |
| Security & Privacy | 5 | Potential |
| Automation & Scripting | 5 | Potential |
| Knowledge & Mathematics | 6 | Potential |
| Creative & Media | 5 | Potential |
| Collaboration & Communication | 3 | Potential |
| Data Science & Analysis | 4 | Potential |
| Location & Maps | 2 | Potential |
| Experimental & Forward-Looking | 6 | Potential |

**Total: 83 potential tools** across 14 categories.

---

*← [Features & Use Cases](vision/04-features-and-use-cases.md) · See also: [Roadmap](vision/06-roadmap.md)*
