import Foundation

// MARK: - ModelInfo (Dynamic, Codable)

/// A model entry populated from the Hugging Face API and persisted to disk.
/// No hardcoded catalog — everything comes from the API or cached JSON.
struct ModelInfo: Identifiable, Hashable, Codable {

    /// HuggingFace repo ID, e.g. "mlx-community/Qwen3-8B-4bit"
    let id: String

    /// Model architecture from config.model_type, e.g. "qwen3", "llama", "gemma3"
    var modelType: String

    /// Quantization bits from config.quantization_config.bits, or from tags
    var quantizationBits: Int?

    /// Total storage used on HF (bytes) — from the usedStorage API field
    var storageSizeBytes: Int64

    /// Download count from HF
    var downloads: Int

    /// Likes count from HF
    var likes: Int

    /// Tags from HF (contains architecture, quantization, license info, etc.)
    var tags: [String]

    /// When this entry was last fetched from the API
    var lastFetched: Date

    // MARK: - Derived display properties

    /// Human-friendly name derived from the repo ID.
    var displayName: String {
        let name = id.components(separatedBy: "/").last ?? id
        return name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    /// The org / author, e.g. "mlx-community"
    var author: String {
        id.components(separatedBy: "/").first ?? ""
    }

    /// Short model name, e.g. "Qwen3-8B-4bit"
    var shortName: String {
        id.components(separatedBy: "/").last ?? id
    }

    /// Family derived from modelType, e.g. "qwen3" -> "Qwen3"
    var family: String {
        let cleaned = modelType
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    /// Quantization label, e.g. "4-bit", "8-bit", or "fp16"
    var quantizationLabel: String {
        if let bits = quantizationBits {
            return "\(bits)-bit"
        }
        if tags.contains("4-bit") { return "4-bit" }
        if tags.contains("8-bit") { return "8-bit" }
        if tags.contains("bf16") { return "bf16" }
        return "unknown"
    }

    /// Formatted storage size, e.g. "2.5 GB"
    var storageSizeLabel: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: storageSizeBytes)
    }

    /// Estimated RAM usage (weights + ~20% overhead for KV cache / tokenizer)
    var estimatedRAMBytes: Int64 {
        Int64(Double(storageSizeBytes) * 1.2)
    }

    /// Formatted RAM estimate, e.g. "3.0 GB"
    var estimatedRAMLabel: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: estimatedRAMBytes)
    }

    /// Formatted download count, e.g. "23.6K"
    var downloadsLabel: String {
        if downloads >= 1_000_000 {
            return String(format: "%.1fM", Double(downloads) / 1_000_000)
        } else if downloads >= 1_000 {
            return String(format: "%.1fK", Double(downloads) / 1_000)
        }
        return "\(downloads)"
    }

    /// Parameter count label extracted from the name, e.g. "8B", "0.6B", "30B-A3B"
    var parameterLabel: String {
        let name = shortName
        let patterns = [
            #"(\d+\.?\d*B-A\d+\.?\d*B)"#,
            #"(\d+\.?\d*[BM])"#,
        ]
        for pattern in patterns {
            if let range = name.range(of: pattern, options: .regularExpression) {
                return String(name[range])
            }
        }
        return ""
    }

    /// Whether this model fits in the given RAM budget
    func fitsInRAM(gbAvailable: Int = 24) -> Bool {
        estimatedRAMBytes < Int64(gbAvailable) * 1_073_741_824
    }

    // MARK: - Local download status

    var isDownloaded: Bool {
        let fm = FileManager.default
        let dir = modelCacheDirectory
        guard fm.fileExists(atPath: dir.path) else { return false }
        if let contents = try? fm.contentsOfDirectory(atPath: dir.path) {
            return contents.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".json") }
        }
        return false
    }

    var downloadedSizeBytes: Int64? {
        let fm = FileManager.default
        let dir = modelCacheDirectory
        guard fm.fileExists(atPath: dir.path) else { return nil }
        return Self.directorySize(url: dir)
    }

    var downloadedSizeLabel: String? {
        guard let bytes = downloadedSizeBytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Delete from disk

    @discardableResult
    func deleteFromDisk() -> Bool {
        let fm = FileManager.default
        let dir = modelCacheDirectory
        guard fm.fileExists(atPath: dir.path) else { return true }
        do {
            try fm.removeItem(at: dir)
            return true
        } catch {
            print("[ModelInfo] Failed to delete \(id): \(error)")
            return false
        }
    }

    // MARK: - Cache directory

    private var modelCacheDirectory: URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDir
            .appending(path: "models", directoryHint: .isDirectory)
            .appending(path: id, directoryHint: .isDirectory)
    }

    // MARK: - Helpers

    private static func directorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ModelInfo, rhs: ModelInfo) -> Bool {
        lhs.id == rhs.id
    }
}
