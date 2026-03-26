import Foundation
import Combine

// MARK: - HF API Response Types (private)

/// Partial model info returned by the HF listing endpoint.
private struct HFModelListEntry: Decodable {
    let id: String
    let tags: [String]?
    let downloads: Int?
    let likes: Int?
    let pipeline_tag: String?
    let library_name: String?
}

/// Full model detail returned by the HF single-model endpoint.
private struct HFModelDetail: Decodable {
    let id: String
    let tags: [String]?
    let downloads: Int?
    let likes: Int?
    let usedStorage: Int64?
    let config: HFConfig?

    struct HFConfig: Decodable {
        let model_type: String?
        let quantization_config: HFQuantConfig?
    }

    struct HFQuantConfig: Decodable {
        let bits: Int?
    }
}

// MARK: - ModelCatalogService

/// Fetches MLX-compatible text-generation models from the Hugging Face API,
/// enriches them with per-model detail (storage size, architecture, quant bits),
/// and persists the catalog to disk as JSON.
@MainActor
final class ModelCatalogService: ObservableObject {

    // MARK: - Published state

    @Published private(set) var models: [ModelInfo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefreshed: Date?

    // MARK: - Configuration

    /// Search queries to find MLX-compatible models. Each query produces a separate API call.
    private let searchQueries = ["mlx-community"]

    /// Maximum models to fetch per query from the listing API.
    private let listLimit = 80

    /// How old the cache can be before auto-refreshing (1 hour).
    private let cacheMaxAge: TimeInterval = 3600

    /// Default model ID to use if nothing is cached yet.
    static let defaultModelID = "mlx-community/Qwen3-8B-4bit"

    // MARK: - Persistence

    private var catalogFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appending(path: "mlx-testing", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "model_catalog.json")
    }

    private var metadataFileURL: URL {
        catalogFileURL.deletingLastPathComponent().appending(path: "catalog_metadata.json")
    }

    // MARK: - Init

    init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// Load cached models from disk, then refresh from API if stale.
    func loadAndRefreshIfNeeded() async {
        loadFromDisk()
        if models.isEmpty || isCacheStale {
            await refreshFromAPI()
        }
    }

    /// Force a full refresh from the HF API.
    func refreshFromAPI() async {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil

        do {
            // Step 1: Fetch listing of MLX text-generation models
            var allIDs: [String] = []
            for query in searchQueries {
                let ids = try await fetchModelList(search: query)
                allIDs.append(contentsOf: ids)
            }
            // Deduplicate while preserving order
            var seen = Set<String>()
            let uniqueIDs = allIDs.filter { seen.insert($0).inserted }

            // Step 2: Fetch detail for each model (with concurrency limit)
            let details = await fetchModelDetails(ids: uniqueIDs)

            // Step 3: Update models array
            let now = Date()
            var newModels: [ModelInfo] = []
            for detail in details {
                let info = ModelInfo(
                    id: detail.id,
                    modelType: detail.config?.model_type ?? inferModelType(from: detail.tags ?? []),
                    quantizationBits: detail.config?.quantization_config?.bits ?? inferQuantBits(from: detail.tags ?? []),
                    storageSizeBytes: detail.usedStorage ?? 0,
                    downloads: detail.downloads ?? 0,
                    likes: detail.likes ?? 0,
                    tags: detail.tags ?? [],
                    lastFetched: now
                )
                // Only include models with known storage size > 0
                if info.storageSizeBytes > 0 {
                    newModels.append(info)
                }
            }

            // Sort by downloads descending
            newModels.sort { $0.downloads > $1.downloads }

            models = newModels
            lastRefreshed = now
            saveToDisk()
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    /// Find a model by ID in the current catalog.
    func find(id: String) -> ModelInfo? {
        models.first { $0.id == id }
    }

    /// All unique family names in the current catalog, in order.
    var families: [String] {
        var seen = Set<String>()
        return models.compactMap { info in
            let f = info.family
            if seen.contains(f) { return nil }
            seen.insert(f)
            return f
        }
    }

    /// Total bytes used by all downloaded models.
    var totalDownloadedSizeBytes: Int64 {
        models.compactMap(\.downloadedSizeBytes).reduce(0, +)
    }

    /// Formatted total storage string.
    var totalDownloadedSizeLabel: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalDownloadedSizeBytes)
    }

    /// Number of models currently cached on disk.
    var downloadedCount: Int {
        models.filter(\.isDownloaded).count
    }

    // MARK: - Private: API Calls

    private func fetchModelList(search: String) async throws -> [String] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "search", value: search),
            URLQueryItem(name: "filter", value: "text-generation"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "\(listLimit)"),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CatalogError.apiError("Failed to fetch model list (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }

        let entries = try JSONDecoder().decode([HFModelListEntry].self, from: data)

        // Filter to only models that have "mlx" in tags and are text-generation
        return entries.filter { entry in
            let tags = entry.tags ?? []
            let hasMlx = tags.contains("mlx") || tags.contains("safetensors")
            let isTextGen = entry.pipeline_tag == "text-generation"
            return hasMlx && isTextGen
        }.map(\.id)
    }

    private func fetchModelDetails(ids: [String]) async -> [HFModelDetail] {
        // Use a TaskGroup with concurrency limit to avoid overwhelming the API
        await withTaskGroup(of: HFModelDetail?.self, returning: [HFModelDetail].self) { group in
            // Limit concurrent requests
            let maxConcurrent = 8
            var index = 0
            var results: [HFModelDetail] = []

            // Seed initial batch
            for _ in 0..<min(maxConcurrent, ids.count) {
                let id = ids[index]
                index += 1
                group.addTask { [weak self] in
                    try? await self?.fetchSingleModelDetail(id: id)
                }
            }

            for await result in group {
                if let detail = result {
                    results.append(detail)
                }
                // Add next task if available
                if index < ids.count {
                    let id = ids[index]
                    index += 1
                    group.addTask { [weak self] in
                        try? await self?.fetchSingleModelDetail(id: id)
                    }
                }
            }

            return results
        }
    }

    private nonisolated func fetchSingleModelDetail(id: String) async throws -> HFModelDetail {
        let urlString = "https://huggingface.co/api/models/\(id)"
        guard let url = URL(string: urlString) else {
            throw CatalogError.apiError("Invalid URL for model: \(id)")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CatalogError.apiError("Failed to fetch detail for \(id)")
        }

        return try JSONDecoder().decode(HFModelDetail.self, from: data)
    }

    // MARK: - Private: Inference helpers

    private func inferModelType(from tags: [String]) -> String {
        // Common model type tags
        let knownTypes = [
            "qwen3", "qwen2", "qwen", "llama", "gemma3", "gemma2", "gemma",
            "mistral", "phi3", "phi", "deepseek", "gpt_oss", "smollm",
            "glm", "granite", "starcoder", "codellama", "yi", "internlm",
            "command-r", "dbrx", "mixtral", "falcon", "mpt", "bloom",
            "kimi_k25", "lfm2_moe", "gpt_oss",
        ]
        for tag in tags {
            let lower = tag.lowercased()
            if knownTypes.contains(lower) {
                return lower
            }
        }
        // Try to infer from the model ID in tags
        for tag in tags where tag.hasPrefix("base_model:") {
            let base = tag.replacingOccurrences(of: "base_model:", with: "")
            let parts = base.lowercased().components(separatedBy: "/")
            if let name = parts.last {
                for t in knownTypes {
                    if name.contains(t) { return t }
                }
            }
        }
        return "unknown"
    }

    private func inferQuantBits(from tags: [String]) -> Int? {
        if tags.contains("4-bit") { return 4 }
        if tags.contains("8-bit") { return 8 }
        if tags.contains("3-bit") { return 3 }
        return nil
    }

    // MARK: - Private: Persistence

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(models)
            try data.write(to: catalogFileURL, options: .atomic)

            // Save metadata
            let metadata = CatalogMetadata(lastRefreshed: lastRefreshed ?? Date(), modelCount: models.count)
            let metaData = try encoder.encode(metadata)
            try metaData.write(to: metadataFileURL, options: .atomic)

            print("[ModelCatalogService] Saved \(models.count) models to disk")
        } catch {
            print("[ModelCatalogService] Failed to save: \(error)")
        }
    }

    private func loadFromDisk() {
        do {
            let data = try Data(contentsOf: catalogFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            models = try decoder.decode([ModelInfo].self, from: data)

            if let metaData = try? Data(contentsOf: metadataFileURL) {
                let metadata = try decoder.decode(CatalogMetadata.self, from: metaData)
                lastRefreshed = metadata.lastRefreshed
            }

            print("[ModelCatalogService] Loaded \(models.count) models from disk")
        } catch {
            print("[ModelCatalogService] No cached catalog found, will fetch from API")
        }
    }

    private var isCacheStale: Bool {
        guard let last = lastRefreshed else { return true }
        return Date().timeIntervalSince(last) > cacheMaxAge
    }

    // MARK: - Types

    private struct CatalogMetadata: Codable {
        let lastRefreshed: Date
        let modelCount: Int
    }

    enum CatalogError: LocalizedError {
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .apiError(let msg): return msg
            }
        }
    }
}
