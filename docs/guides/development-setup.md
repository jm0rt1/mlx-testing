# Development Setup

> How to set up your environment, build, and run MLX Copilot for development.

---

## Prerequisites

| Requirement | Minimum | Recommended |
|---|---|---|
| Mac | Apple Silicon (M1 or later) | M1 Pro/Max or later |
| macOS | 14.0 Sonoma | Latest stable |
| Xcode | 16.0 | Latest stable |
| RAM | 16 GB | 24 GB+ |
| Disk space | 10 GB free | 30 GB+ (for multiple model downloads) |

> **Note:** MLX requires Apple Silicon. Intel Macs are not supported.

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/jm0rt1/mlx-testing.git
cd mlx-testing
```

### 2. Open in Xcode

```bash
open mlx-testing.xcodeproj
```

### 3. Configure signing

In Xcode:
1. Select the **mlx-testing** target
2. Go to **Signing & Capabilities**
3. Set your **Team** (personal or organizational)

### 4. Resolve packages

Xcode should automatically resolve Swift Package Manager dependencies. If not:

- **File → Packages → Resolve Package Versions**

The project depends on:
- `mlx-swift` (0.30.x) — MLX array framework
- `mlx-swift-lm` (2.30.x) — LLM/VLM support

### 5. Build and run

- **⌘B** to build
- **⌘R** to run

On first launch, the app will:
1. Fetch the model catalog from HuggingFace API
2. Download the default model (~5 GB for Qwen3-8B-4bit)
3. Load the model into GPU memory

> **Tip:** For faster inference during development, run without the debugger: **⌘⌥R** → uncheck "Debug Executable" → Run.

---

## Development Workflows

### Using Stub Mode

For UI development without downloading a model:

1. In `ChatViewModel.swift`, change the default backend:
   ```swift
   init(backend: LLMBackend = .stub)
   ```
2. Or switch at runtime using the **Backend** picker in the toolbar

Stub mode simulates streaming responses with no network or GPU required.

### Switching Models

- **At runtime:** Use the Model Picker toolbar popover (⌘M or click the model name)
- **Default model:** Change `ModelCatalogService.defaultModelID`:
  ```swift
  static let defaultModelID = "mlx-community/Qwen3-8B-4bit"
  ```

### Adjusting Generation Parameters

In `LocalLLMService.swift` → `LocalLLMServiceMLX`:

```swift
var generateParameters = GenerateParameters(maxTokens: 2048, temperature: 0.6)
```

---

## Project Layout

```
mlx-testing/
├── mlx-testing.xcodeproj         # Xcode project file
├── README.md                      # Project README
├── docs/                          # Documentation
│   ├── vision/                    #   Product vision documents
│   ├── design/                    #   Technical design documents
│   ├── guides/                    #   Developer guides (you are here)
│   └── decisions/                 #   Architectural decision records
└── mlx-testing/                   # Source code
    ├── mlx_testingApp.swift       #   App entry point
    ├── ContentView.swift          #   Main UI
    ├── ChatViewModel.swift        #   View model
    ├── ChatMessage.swift          #   Message data model
    ├── LocalLLMService.swift      #   LLM service protocol + implementations
    ├── ModelInfo.swift            #   Model metadata
    ├── ModelCatalogService.swift  #   HF API catalog
    ├── ModelPickerView.swift      #   Model picker UI
    ├── MarkdownView.swift         #   Markdown renderer
    ├── ContextBubble.swift        #   Context bubble data model
    ├── ContextBubbleEditor.swift  #   Context bubble sidebar UI
    ├── ContextStore.swift         #   Context persistence
    ├── SystemPromptEditor.swift   #   System prompt editor UI
    ├── AgentTools/                #   Agent tool system
    │   ├── AgentTool.swift
    │   ├── ToolRegistry.swift
    │   ├── ToolExecutor.swift
    │   ├── FileSystemTool.swift
    │   ├── ShellCommandTool.swift
    │   ├── ClipboardTool.swift
    │   └── AppLauncherTool.swift
    └── mlx_testing.entitlements   #   Sandbox entitlements
```

---

## Build Notes

### No Command-Line Build

The project relies on Xcode for building. There is no `swift build` support because:
- MLX frameworks require specific linker flags managed by Xcode
- The app sandbox requires code signing
- Entitlements are applied during the Xcode build process

### No Unit Tests (Yet)

There are currently no unit tests or CI workflows. Testing is manual. When unit tests are added, they should:
- Use XCTest framework
- Test data models, services, and view models (not views)
- Use `LocalLLMServiceStub` for tests that involve generation

### Package Resolution Issues

If Xcode shows package resolution errors:

1. **File → Packages → Reset Package Caches**
2. **File → Packages → Resolve Package Versions**
3. If persistent: delete `~/Library/Developer/Xcode/DerivedData/mlx-testing-*`

---

## App Data Locations

During development, the app stores data in these locations:

| Data | Path |
|---|---|
| Context bubbles | `~/Library/Application Support/mlx-testing/contexts.json` |
| System prompt | `~/Library/Application Support/mlx-testing/system_prompt.txt` |
| Model catalog | `~/Library/Application Support/mlx-testing/model_catalog.json` |
| Model weights | `~/Library/Caches/models/` |
| UserDefaults | `~/Library/Preferences/com.yourteam.mlx-testing.plist` |

To reset the app to a clean state:

```bash
rm -rf ~/Library/Application\ Support/mlx-testing/
defaults delete com.yourteam.mlx-testing
```

> **Caution:** This also removes downloaded model catalog data. Model weights in `~/Library/Caches/models/` are managed by MLX and can be deleted separately if needed.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| "Failed to load" on launch | Check internet connection for model download |
| Build error: missing modules | File → Packages → Resolve Package Versions |
| Slow first token | Normal — model loads into GPU memory on first use |
| App uses too much memory | Try a smaller model (1B–3B) or reduce `maxTokens` |
| Sandbox error on file access | Verify entitlements in `mlx_testing.entitlements` |
| Package resolution hangs | Reset Package Caches, then Resolve again |

---

*Related: [Contributing Guide](contributing.md) · [Adding Tools Guide](adding-tools.md)*
