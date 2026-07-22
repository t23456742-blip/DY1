import Foundation
import Darwin

/// 扫描器 — 用 shell 命令绕沙箱，跟 FUCK 工具箱同原理
final class FileScanner {
    static let containerBase = "/var/mobile/Containers/Data/Application"

    static let targetBundleIds = [
        "com.ss.iphone.ugc.Aweme",
        "com.ss.iphone.ugc.Live",
        "com.ss.iphone.ugc.Lite",
        "com.zhiliaoapp.musically",
    ]

    static let safePaths: [(String, String)] = [
        ("Library/Caches", "应用缓存"),
        ("tmp", "临时文件"),
        ("Library/SplashBoard", "启动图快照"),
        ("Library/Caches/Snapshots", "多任务快照"),
    ]

    static let standardPaths: [(String, String)] = [
        ("Library/WebKit", "WebView 缓存"),
        ("Library/Cookies", "过期 Cookie"),
        ("Documents/aweme_stat", "统计数据"),
        ("Documents/aweme_log", "日志文件"),
        ("Documents/BDHLog", "下载日志"),
        ("Documents/offline_pkg", "离线包缓存"),
    ]

    static let deepPaths: [(String, String)] = [
        ("Documents/aweme_video_cache", "视频预加载"),
        ("Documents/persistence/video", "视频持久化"),
    ]

    // MARK: - Shell 工具 (绕沙箱)
    private static func sh(_ cmd: String) -> String {
        let fp = popen(cmd, "r")
        guard fp != nil else { return "" }
        var out = ""
        var buf = [CChar](repeating: 0, count: 4096)
        while fgets(&buf, Int32(buf.count), fp) != nil {
            out += String(cString: buf)
        }
        pclose(fp)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 扫描
    static func scanAll() -> [AppInfo] {
        var apps: [AppInfo] = []

        let ls = sh("ls '\(containerBase)' 2>/dev/null")
        guard !ls.isEmpty else { return apps }

        for uuid in ls.components(separatedBy: .newlines) where !uuid.isEmpty {
            let dir = "\(containerBase)/\(uuid)"
            // 确认是目录
            let test = sh("test -d '\(dir)' && echo 1 || echo 0")
            guard test == "1" else { continue }

            // 检查元数据文件
            let meta = "\(dir)/.com.apple.mobile_container_manager.metadata.plist"
            guard sh("test -f '\(meta)' && echo 1") == "1" else { continue }

            // 用 plutil 解析 Bundle ID
            let plist = sh("plutil -p '\(meta)' 2>/dev/null")
            guard let bid = extractBid(from: plist) else { continue }
            guard targetBundleIds.contains(bid) else { continue }

            // 用 du 获取大小
            let totalSize = Int64(sh("du -sk '\(dir)' 2>/dev/null | awk '{print $1}'")) ?? 0
            let totalSizeBytes = totalSize * 1024
            let cacheSize = estimateCacheSize(dir)

            apps.append(AppInfo(
                bundleId: bid, containerPath: dir,
                totalSize: totalSizeBytes, cacheSize: cacheSize
            ))
        }
        return apps.sorted { $0.totalSize > $1.totalSize }
    }

    private static func extractBid(from plist: String) -> String? {
        for line in plist.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.contains("MCMMetadataIdentifier") else { continue }
            // plutil -p 格式: "MCMMetadataIdentifier" => "com.xxx.yyy"
            let parts = t.components(separatedBy: "\"")
            if parts.count >= 4 { return parts[3] }
        }
        return nil
    }

    static func estimateCacheSize(_ container: String) -> Int64 {
        var total: Int64 = 0
        for (rel, _) in safePaths + standardPaths + deepPaths {
            let kb = sh("du -sk '\(container)/\(rel)' 2>/dev/null | awk '{print $1}'")
            if let k = Int64(kb) { total += k * 1024 }
        }
        return total
    }

    /// 用 du -sk 获取目录字节数
    static func duSize(_ path: String) -> Int64 {
        let kb = sh("du -sk '\(path)' 2>/dev/null | awk '{print $1}'")
        return (Int64(kb) ?? 0) * 1024
    }

    static func paths(for level: CleanLevel) -> [(String, String)] {
        switch level {
        case .safe:    return safePaths
        case .standard: return safePaths + standardPaths
        case .deep:     return safePaths + standardPaths + deepPaths
        }
    }
}
