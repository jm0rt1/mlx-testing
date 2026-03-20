import Combine
import Foundation
import SwiftUI

/// Manages persistence of ContextBubbles and the base system prompt.
///
/// Data is stored in `~/Library/Application Support/mlx-testing/`:
///   - `contexts.json`  – array of ContextBubble
///   - `system_prompt.txt` – base system prompt text
///
/// On first launch, seeds with `ContextBubble.defaults`.
@MainActor
final class ContextStore: ObservableObject {

    // ── Published state ────────────────────────────────────────────────
    @Published var bubbles: [ContextBubble] = []
    @Published var systemPrompt: String = "You are a friendly, concise, and helpful assistant."

    // ── File paths ─────────────────────────────────────────────────────
    private let storeDirectory: URL
    private var contextsFileURL: URL { storeDirectory.appending(path: "contexts.json") }
    private var promptFileURL: URL  { storeDirectory.appending(path: "system_prompt.txt") }

    // ── Debounced auto-save ────────────────────────────────────────────
    private var saveCancellable: AnyCancellable?

    // ── Init ───────────────────────────────────────────────────────────

    init() {
        // ~/Library/Application Support/mlx-testing/
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        storeDirectory = appSupport.appending(path: "mlx-testing")

        ensureDirectory()
        loadAll()
        startAutoSave()
    }

    // MARK: - Composed Prompt

    /// Returns the full system prompt: base prompt + all enabled context bubbles.
    var composedSystemPrompt: String {
        var parts = [systemPrompt]

        let enabledByType: [(ContextBubble.BubbleType, String)] = [
            (.skill, "Skills"),
            (.instruction, "Instructions"),
            (.memory, "Memory"),
            (.custom, "Context"),
        ]

        for (type, header) in enabledByType {
            let items = bubbles.filter { $0.type == type && $0.isEnabled }
            if !items.isEmpty {
                parts.append("[\(header)]")
                for item in items {
                    parts.append("- \(item.name): \(item.content)")
                }
            }
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - CRUD

    func add(_ bubble: ContextBubble) {
        bubbles.append(bubble)
    }

    func update(_ bubble: ContextBubble) {
        if let idx = bubbles.firstIndex(where: { $0.id == bubble.id }) {
            var updated = bubble
            updated.updatedAt = Date()
            bubbles[idx] = updated
        }
    }

    func delete(_ bubble: ContextBubble) {
        bubbles.removeAll { $0.id == bubble.id }
    }

    func toggle(_ bubble: ContextBubble) {
        if let idx = bubbles.firstIndex(where: { $0.id == bubble.id }) {
            bubbles[idx].isEnabled.toggle()
            bubbles[idx].updatedAt = Date()
        }
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        bubbles.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Persistence

    func saveAll() {
        saveBubbles()
        savePrompt()
    }

    private func loadAll() {
        loadBubbles()
        loadPrompt()
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
    }

    private func saveBubbles() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(bubbles)
            try data.write(to: contextsFileURL, options: .atomic)
        } catch {
            print("[ContextStore] Failed to save contexts: \(error)")
        }
    }

    private func loadBubbles() {
        guard FileManager.default.fileExists(atPath: contextsFileURL.path) else {
            // First launch → seed defaults
            bubbles = ContextBubble.defaults
            saveBubbles()
            return
        }
        do {
            let data = try Data(contentsOf: contextsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            bubbles = try decoder.decode([ContextBubble].self, from: data)
        } catch {
            print("[ContextStore] Failed to load contexts: \(error)")
            bubbles = ContextBubble.defaults
        }
    }

    private func savePrompt() {
        do {
            try systemPrompt.write(to: promptFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("[ContextStore] Failed to save system prompt: \(error)")
        }
    }

    private func loadPrompt() {
        guard FileManager.default.fileExists(atPath: promptFileURL.path) else {
            savePrompt() // persist default
            return
        }
        do {
            systemPrompt = try String(contentsOf: promptFileURL, encoding: .utf8)
        } catch {
            print("[ContextStore] Failed to load system prompt: \(error)")
        }
    }

    /// Auto-save whenever bubbles or systemPrompt change (debounced 1s).
    private func startAutoSave() {
        saveCancellable = Publishers.Merge(
            $bubbles.map { _ in () },
            $systemPrompt.map { _ in () }
        )
        .debounce(for: .seconds(1), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.saveAll()
        }
    }
}
