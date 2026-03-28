# SystemInfoTool

**Category:** macOS System & Hardware
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `system_info`

## Overview

`SystemInfoTool` exposes live hardware and OS telemetry to the LLM. It is read-only and requires no special sandbox entitlements beyond what every process has by default. Typical uses include answering "how much RAM do I have free?" or "what macOS version am I running?" without leaving the chat.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `query` | string | Yes | — | Category of information to return. One of `cpu`, `memory`, `gpu`, `battery`, `disk`, `os`, `all` |

---

## Swift Implementation

```swift
import Foundation
import IOKit
import IOKit.ps

struct SystemInfoTool: AgentTool {

    let name = "system_info"
    let toolDescription = "Query live hardware and OS information."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "query", type: .string,
                      description: "Category: cpu | memory | gpu | battery | disk | os | all",
                      required: true,
                      enumValues: ["cpu", "memory", "gpu", "battery", "disk", "os", "all"]),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let query = arguments["query"]?.stringValue else {
            throw ToolError.missingRequiredParameter("query")
        }
        let all = query == "all"
        var sections: [String] = []
        if all || query == "cpu"     { sections.append(cpuInfo()) }
        if all || query == "memory"  { sections.append(memoryInfo()) }
        if all || query == "gpu"     { sections.append(gpuInfo()) }
        if all || query == "battery" { sections.append(batteryInfo()) }
        if all || query == "disk"    { sections.append(diskInfo()) }
        if all || query == "os"      { sections.append(osInfo()) }
        guard !sections.isEmpty else {
            throw ToolError.executionFailed("Unknown query '\(query)'. Use: cpu, memory, gpu, battery, disk, os, all")
        }
        return ToolResult(toolName: name, success: true, output: sections.joined(separator: "\n\n"))
    }

    // MARK: - Queries

    private func cpuInfo() -> String { /* sysctlbyname("machdep.cpu.brand_string") + host_cpu_load_info */ "## CPU\n..." }
    private func memoryInfo() -> String { /* ProcessInfo.physicalMemory + host_statistics64(HOST_VM_INFO64) */ "## Memory\n..." }
    private func gpuInfo() -> String { /* IOServiceGetMatchingServices("IOPCIDevice") */ "## GPU\n..." }
    private func batteryInfo() -> String { /* IOPSCopyPowerSourcesInfo() */ "## Battery\n..." }
    private func diskInfo() -> String { /* FileManager.attributesOfFileSystem */ "## Disk\n..." }
    private func osInfo() -> String { /* ProcessInfo.operatingSystemVersion + kern.osversion sysctl */ "## OS\n..." }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `Foundation` — `ProcessInfo`, `FileManager` | Total RAM, OS version, host name, disk attributes |
| Darwin `sysctlbyname` | CPU brand string (`machdep.cpu.brand_string`), core counts (`hw.physicalcpu`), build string (`kern.osversion`) |
| Mach `host_statistics` / `host_statistics64` | Per-CPU tick counts (`HOST_CPU_LOAD_INFO`), VM page statistics (`HOST_VM_INFO64`) |
| `IOKit` / `IOKit.ps` | Battery info via `IOPSCopyPowerSourcesInfo`; GPU model via `IOServiceGetMatchingServices("IOPCIDevice")` |

### Key Implementation Steps

1. **CPU** — call `sysctlbyname("machdep.cpu.brand_string")` for the model name; read tick buckets from `host_cpu_load_info` and compute `(1 − idle_ticks / total_ticks) × 100`.
2. **Memory** — `ProcessInfo.processInfo.physicalMemory` for total installed RAM; call `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)` to get free/active/wired page counts, multiply by `vm_kernel_page_size`.
3. **GPU** — iterate `IOPCIDevice` service entries; read the `"model"` property as `Data` and decode as UTF-8. On Apple Silicon the integrated GPU appears under `AGXAccelerator`.
4. **Battery** — use `IOPSCopyPowerSourcesInfo()` + `IOPSCopyPowerSourcesList()` + `IOPSGetPowerSourceDescription()` to read capacity, charging state, and cycle count.
5. **Disk** — `FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())` returns `.systemFreeSize` and `.systemSize`. For multiple volumes, enumerate `FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:)`.
6. **OS** — `ProcessInfo.processInfo.operatingSystemVersion` for major/minor/patch; `kern.osversion` sysctl for the build string.

### Output Truncation

Not applicable. Responses are short by nature (< 500 characters per query).

---

## Sandbox Entitlements

No additional entitlements are required. `sysctlbyname`, `host_statistics`, `IOPowerSources`, and `FileManager` are available to sandboxed apps.

---

## Example Tool Call

```json
{"tool": "system_info", "arguments": {"query": "memory"}}
```

**Example output:**
```
## Memory
Total: 16 GB
Free: 4.2 GB
Active: 7.8 GB
Wired: 3.1 GB
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Unknown `query` value | Throws `ToolError.executionFailed` listing valid values |
| `host_statistics64` fails | Omits affected sub-section; includes a `(data unavailable)` note |
| No battery (desktop Mac) | Returns `"No battery detected"` |
| GPU not enumerable in sandbox | Returns `"(GPU info not available)"` |

---

## Edge Cases

- **Apple Silicon** — `machdep.cpu.brand_string` returns `"Apple M3"` on ARM Macs; the GPU is part of the SoC and appears under `AGXAccelerator`, not `IOPCIDevice`.
- **Multiple disks** — extend with `FileManager.mountedVolumeURLs` to report all volumes instead of only the boot volume.
- **Memory pressure level** — the kernel's `memorystatus_vm_pressure_level` sysctl (`1`=normal, `2`=warning, `4`=critical) can be added as an extra field.

---

## See Also

- [ProcessManagerTool](./ProcessManagerTool.md)
- [DisplayTool](./DisplayTool.md)
