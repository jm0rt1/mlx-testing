import Foundation
import Hub
import MLXLLM
import MLXLMCommon

// MARK: - ModelInfo

/// Describes an available model with its size, memory requirements, and download status.
struct ModelInfo: Identifiable, Hashable {
    let id: String                        // HuggingFace repo ID, e.g. "mlx-community/Qwen3-8B-4bit"
    let displayName: String               // Short human name, e.g. "Qwen3 8B 4-bit"
    let family: String                    // e.g. "Qwen3", "Llama 3", "Gemma"
    let parameterLabel: String            // e.g. "8B", "4B", "30B-A3B"
    let quantization: String              // e.g. "4-bit", "bf16"
    let diskSizeMB: Int                   // Approximate download size in MB
    let ramSizeMB: Int                    // Approximate runtime memory in MB
    let configuration: ModelConfiguration // The actual MLX config for loading
    let note: String?                     // Optional note, e.g. "MoE – only 3B active"

    // Identifiable via the HF repo ID
    var hashableID: String { id }

    // MARK: - Download status

    /// Checks whether the model weights appear to be cached locally.
    /// MLX downloads to `~/Library/Caches/huggingface/hub/models--<org>--<name>/`.
    var isDownloaded: Bool {
        let fm = FileManager.default
        let dir = modelCacheDirectory
        guard fm.fileExists(atPath: dir.path) else { return false }
        // Look for .safetensors files as proof of a complete download
        if let contents = try? fm.contentsOfDirectory(atPath: dir.path) {
            return contents.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".json") }
        }
        return false
    }

    /// Returns the actual size on disk if downloaded, in bytes.
    var downloadedSizeBytes: Int64? {
        let fm = FileManager.default
        let dir = modelCacheDirectory
        guard fm.fileExists(atPath: dir.path) else { return nil }
        return Self.directorySize(url: dir)
    }

    /// Formatted disk size string for display.
    var diskSizeLabel: String {
        Self.formatMB(diskSizeMB)
    }

    /// Formatted RAM size string for display.
    var ramSizeLabel: String {
        Self.formatMB(ramSizeMB)
    }

    /// Formatted actual-on-disk size if downloaded.
    var downloadedSizeLabel: String? {
        guard let bytes = downloadedSizeBytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Helpers

    /// The cache directory used by HubApi (default download base is Caches).
    private var modelCacheDirectory: URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        // HubApi stores at: <downloadBase>/models/<org>/<model>
        return cachesDir
            .appending(path: "models", directoryHint: .isDirectory)
            .appending(path: id, directoryHint: .isDirectory)
    }

    private static func formatMB(_ mb: Int) -> String {
        if mb >= 1024 {
            let gb = Double(mb) / 1024.0
            return String(format: "%.1f GB", gb)
        }
        return "\(mb) MB"
    }

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

// MARK: - Model Catalog

extension ModelInfo {

    /// All models available for selection. Ordered by family then size.
    static let catalog: [ModelInfo] = [

        // ── Gemma ──────────────────────────────────────────────────
        ModelInfo(
            id: "mlx-community/gemma-3-1b-it-qat-4bit",
            displayName: "Gemma 3 1B QAT",
            family: "Gemma", parameterLabel: "1B", quantization: "4-bit",
            diskSizeMB: 700, ramSizeMB: 900,
            configuration: LLMRegistry.gemma3_1B_qat_4bit,
            note: "Ultra-lightweight, great for testing"
        ),
        ModelInfo(
            id: "mlx-community/gemma-2-2b-it-4bit",
            displayName: "Gemma 2 2B",
            family: "Gemma", parameterLabel: "2B", quantization: "4-bit",
            diskSizeMB: 1500, ramSizeMB: 1800,
            configuration: LLMRegistry.gemma_2_2b_it_4bit,
            note: nil
        ),
        ModelInfo(
            id: "mlx-community/gemma-2-9b-it-4bit",
            displayName: "Gemma 2 9B",
            family: "Gemma", parameterLabel: "9B", quantization: "4-bit",
            diskSizeMB: 5500, ramSizeMB: 6200,
            configuration: LLMRegistry.gemma_2_9b_it_4bit,
            note: nil
        ),

        // ── Qwen3 ─────────────────────────────────────────────────
        ModelInfo(
            id: "mlx-community/Qwen3-0.6B-4bit",
            displayName: "Qwen3 0.6B",
            family: "Qwen3", parameterLabel: "0.6B", quantization: "4-bit",
            diskSizeMB: 400, ramSizeMB: 600,
            configuration: LLMRegistry.qwen3_0_6b_4bit,
            note: "Tiny, fast experiments"
        ),
        ModelInfo(
            id: "mlx-community/Qwen3-1.7B-4bit",
            displayName: "Qwen3 1.7B",
            family: "Qwen3", parameterLabel: "1.7B", quantization: "4-bit",
            diskSizeMB: 1100, ramSizeMB: 1400,
            configuration: LLMRegistry.qwen3_1_7b_4bit,
            note: nil
        ),
        ModelInfo(
            id: "mlx-community/Qwen3-4B-4bit",
            displayName: "Qwen3 4B",
            family: "Qwen3", parameterLabel: "4B", quantization: "4-bit",
            diskSizeMB: 2500, ramSizeMB: 3000,
            configuration: LLMRegistry.qwen3_4b_4bit,
            note: "Good quality / speed balance"
        ),
        ModelInfo(
            id: "mlx-community/Qwen3-8B-4bit",
            displayName: "Qwen3 8B",
            family: "Qwen3", parameterLabel: "8B", quantization: "4-bit",
            diskSizeMB: 5000, ramSizeMB: 5500,
            configuration: LLMRegistry.qwen3_8b_4bit,
            note: "Recommended for 24 GB"
        ),
        ModelInfo(
            id: "mlx-community/Qwen3-30B-A3B-4bit",
            displayName: "Qwen3 MoE 30B-A3B",
            family: "Qwen3", parameterLabel: "30B-A3B", quantization: "4-bit",
            diskSizeMB: 17000, ramSizeMB: 18000,
            configuration: LLMRegistry.qwen3MoE_30b_a3b_4bit,
            note: "MoE — only 3B active per token, tight fit on 24 GB"
        ),

        // ── Llama ──────────────────────────────────────────────────
        ModelInfo(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            displayName: "Llama 3.2 1B",
            family: "Llama", parameterLabel: "1B", quantization: "4-bit",
            diskSizeMB: 750, ramSizeMB: 1000,
            configuration: LLMRegistry.llama3_2_1B_4bit,
            note: nil
        ),
        ModelInfo(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            displayName: "Llama 3.2 3B",
            family: "Llama", parameterLabel: "3B", quantization: "4-bit",
            diskSizeMB: 2000, ramSizeMB: 2400,
            configuration: LLMRegistry.llama3_2_3B_4bit,
            note: nil
        ),
        ModelInfo(
            id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            displayName: "Llama 3.1 8B",
            family: "Llama", parameterLabel: "8B", quantization: "4-bit",
            diskSizeMB: 4800, ramSizeMB: 5200,
            configuration: LLMRegistry.llama3_1_8B_4bit,
            note: nil
        ),

        // ── Mistral ────────────────────────────────────────────────
        ModelInfo(
            id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            displayName: "Mistral 7B v0.3",
            family: "Mistral", parameterLabel: "7B", quantization: "4-bit",
            diskSizeMB: 4200, ramSizeMB: 4800,
            configuration: LLMRegistry.mistral7B4bit,
            note: nil
        ),

        // ── DeepSeek ───────────────────────────────────────────────
        ModelInfo(
            id: "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit",
            displayName: "DeepSeek R1 Distill 7B",
            family: "DeepSeek", parameterLabel: "7B", quantization: "4-bit",
            diskSizeMB: 4500, ramSizeMB: 5000,
            configuration: LLMRegistry.deepSeekR1_7B_4bit,
            note: "Reasoning model"
        ),

        // ── SmolLM ─────────────────────────────────────────────────
        ModelInfo(
            id: "mlx-community/SmolLM-135M-Instruct-4bit",
            displayName: "SmolLM 135M",
            family: "SmolLM", parameterLabel: "135M", quantization: "4-bit",
            diskSizeMB: 100, ramSizeMB: 200,
            configuration: LLMRegistry.smolLM_135M_4bit,
            note: "Extremely small, good for smoke testing"
        ),
        ModelInfo(
            id: "mlx-community/SmolLM3-3B-4bit",
            displayName: "SmolLM3 3B",
            family: "SmolLM", parameterLabel: "3B", quantization: "4-bit",
            diskSizeMB: 2000, ramSizeMB: 2300,
            configuration: LLMRegistry.smollm3_3b_4bit,
            note: nil
        ),

        // ── GLM ────────────────────────────────────────────────────
        ModelInfo(
            id: "mlx-community/GLM-4-9B-0414-4bit",
            displayName: "GLM-4 9B",
            family: "GLM", parameterLabel: "9B", quantization: "4-bit",
            diskSizeMB: 5500, ramSizeMB: 6000,
            configuration: LLMRegistry.glm4_9b_4bit,
            note: "Tool calling support"
        ),

        // ── Phi ────────────────────────────────────────────────────
        ModelInfo(
            id: "mlx-community/Phi-3.5-mini-instruct-4bit",
            displayName: "Phi 3.5 Mini",
            family: "Phi", parameterLabel: "3.8B", quantization: "4-bit",
            diskSizeMB: 2300, ramSizeMB: 2800,
            configuration: LLMRegistry.phi3_5_4bit,
            note: nil
        ),

        // ── Granite ────────────────────────────────────────────────
        ModelInfo(
            id: "mlx-community/granite-3.3-2b-instruct-4bit",
            displayName: "Granite 3.3 2B",
            family: "Granite", parameterLabel: "2B", quantization: "4-bit",
            diskSizeMB: 1500, ramSizeMB: 1800,
            configuration: LLMRegistry.granite3_3_2b_4bit,
            note: nil
        ),
    ]

    /// The default model to use on first launch.
    static let defaultModel = catalog.first { $0.id == "mlx-community/Qwen3-8B-4bit" }!

    /// Look up a ModelInfo by its HuggingFace ID.
    static func find(id: String) -> ModelInfo? {
        catalog.first { $0.id == id }
    }

    /// All unique model families, in catalog order.
    static var families: [String] {
        var seen = Set<String>()
        return catalog.compactMap { info in
            if seen.contains(info.family) { return nil }
            seen.insert(info.family)
            return info.family
        }
    }
}
