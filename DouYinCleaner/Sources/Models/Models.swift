import Foundation

/// 清理结果
struct CleanResult {
    let freedBytes: Int64
    let beforeBytes: Int64
    let afterBytes: Int64
    let cleanedPaths: [CleanPathDetail]
    let errors: [String]

    var savedPercent: Int {
        beforeBytes > 0 ? Int(freedBytes * 100 / beforeBytes) : 0
    }

    var freedFormatted: String { formatBytes(freedBytes) }
    var beforeFormatted: String { formatBytes(beforeBytes) }
    var afterFormatted: String { formatBytes(afterBytes) }
}

struct CleanPathDetail: Identifiable {
    let id = UUID()
    let path: String
    let description: String
    let bytesFreed: Int64
    let success: Bool
}

/// 清理级别
enum CleanLevel: String, CaseIterable, Identifiable {
    case safe = "安全"
    case standard = "标准"
    case deep = "深度"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .safe: return "🛡️"
        case .standard: return "🧹"
        case .deep: return "💣"
        }
    }
    var description: String {
        switch self {
        case .safe: return "仅删缓存/临时文件, 完全无风险"
        case .standard: return "安全 + WebView/日志/统计"
        case .deep: return "标准 + 视频缓存, 效果最猛"
        }
    }
}

/// App 信息
struct AppInfo: Identifiable {
    let id = UUID()
    let bundleId: String
    let containerPath: String
    var displayName: String { bundleIdToName(bundleId) }
    var totalSize: Int64 = 0
    var cacheSize: Int64 = 0
    var isSelected: Bool = true

    var totalSizeFormatted: String { formatBytes(totalSize) }
    var cacheSizeFormatted: String { formatBytes(cacheSize) }

    private func bundleIdToName(_ id: String) -> String {
        switch id {
        case "com.ss.iphone.ugc.Aweme": return "抖音"
        case "com.ss.iphone.ugc.Live": return "抖音火山版"
        case "com.ss.iphone.ugc.Lite": return "抖音极速版"
        case "com.zhiliaoapp.musically": return "TikTok"
        default: return id
        }
    }
}

// MARK: - Helpers

func formatBytes(_ bytes: Int64) -> String {
    if bytes >= 1_073_741_824 {
        String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    } else if bytes >= 1_048_576 {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    } else if bytes >= 1_024 {
        String(format: "%.1f KB", Double(bytes) / 1_024)
    } else {
        "\(bytes) B"
    }
}
