import Combine
import Foundation

@MainActor
final class TaskBoardStore: ObservableObject {
    @Published var items: [TaskBoardItem] = []

    private let storeDirectory: URL
    private var boardFileURL: URL { storeDirectory.appending(path: "taskboard.json") }
    private var saveCancellable: AnyCancellable?

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        storeDirectory = appSupport.appending(path: "mlx-testing")

        ensureDirectory()
        load()
        startAutoSave()
    }

    var activeItems: [TaskBoardItem] {
        items
            .filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var backlogItems: [TaskBoardItem] {
        items
            .filter { $0.status == .backlog }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var maintenanceItems: [TaskBoardItem] {
        items
            .filter { $0.status == .maintenance }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var completedItems: [TaskBoardItem] {
        items
            .filter { $0.status == .completed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var promptContext: String {
        var parts: [String] = []

        if let active = activeItems.first {
            parts.append("[Active Goal]\n- Title: \(active.title)\n- Next action: \(active.nextAction)")
        }

        let backlog = backlogItems.prefix(3)
        if !backlog.isEmpty {
            let lines = backlog.map { "- \($0.title): \($0.nextAction)" }.joined(separator: "\n")
            parts.append("[Backlog]\n\(lines)")
        }

        return parts.joined(separator: "\n\n")
    }

    func add(_ item: TaskBoardItem) {
        var newItem = item
        newItem.updatedAt = Date()
        if newItem.status == .active {
            demoteActiveItems()
        }
        items.append(newItem)
    }

    func update(_ item: TaskBoardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.updatedAt = Date()
        if updated.status == .active {
            demoteActiveItems(except: updated.id)
        }
        items[index] = updated
    }

    func delete(_ item: TaskBoardItem) {
        items.removeAll { $0.id == item.id }
    }

    func promoteToActive(_ item: TaskBoardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        demoteActiveItems(except: item.id)
        items[index].status = .active
        items[index].updatedAt = Date()
    }

    func markCompleted(_ item: TaskBoardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].status = .completed
        items[index].updatedAt = Date()
    }

    private func demoteActiveItems(except itemID: UUID? = nil) {
        for index in items.indices {
            guard items[index].status == .active else { continue }
            if let itemID, items[index].id == itemID { continue }
            items[index].status = .backlog
            items[index].updatedAt = Date()
        }
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: boardFileURL, options: .atomic)
        } catch {
            print("[TaskBoardStore] Failed to save taskboard: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: boardFileURL.path) else {
            items = []
            save()
            return
        }

        do {
            let data = try Data(contentsOf: boardFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([TaskBoardItem].self, from: data)
        } catch {
            print("[TaskBoardStore] Failed to load taskboard: \(error)")
            items = []
        }
    }

    private func startAutoSave() {
        saveCancellable = $items
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.save()
            }
    }
}
