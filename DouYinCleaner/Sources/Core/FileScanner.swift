import Foundation
import Darwin

/// 扫描器 — 用 posix_spawn 绕沙箱
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

    // MARK: - Shell
    static func sh(_ cmd: String) -> String {
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sh"), strdup("-c"), strdup(cmd), nil]
        defer { for a in argv { free(a) } }
        var pid: pid_t = 0
        var fds: [Int32] = [0, 0]
        pipe(&fds)
        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO)
        posix_spawn_file_actions_addclose(&actions, fds[0])
        let r = posix_spawn(&pid, "/bin/sh", &actions, nil, argv, environ)
        posix_spawn_file_actions_destroy(&actions)
        close(fds[1])
        guard r == 0 else { return "" }
        var out = ""
        var buf = [CChar](repeating: 0, count: 8192)
        while true { let n = read(fds[0], &buf, buf.count); if n <= 0 { break }; out += String(bytes: Data(bytes: buf, count: n), encoding: .utf8) ?? "" }
        close(fds[0])
        var st: Int32 = 0; waitpid(pid, &st, 0)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 扫描
    static func scanAll() -> [AppInfo] {
        var apps: [AppInfo] = []
        let ls = sh("ls '\(containerBase)' 2>/dev/null")
        guard !ls.isEmpty else { return apps }
        for uuid in ls.components(separatedBy: .newlines) where !uuid.isEmpty {
            let dir = "\(containerBase)/\(uuid)"
            guard sh("test -d '\(dir)' && echo 1") == "1" else { continue }
            let meta = "\(dir)/.com.apple.mobile_container_manager.metadata.plist"
            guard sh("test -f '\(meta)' && echo 1") == "1" else { continue }
            let plist = sh("plutil -p '\(meta)' 2>/dev/null")
            guard let bid = extractBid(from: plist) else { continue }
            guard targetBundleIds.contains(bid) else { continue }
            let totalKb = Int64(sh("du -sk '\(dir)' 2>/dev/null | awk '{print $1}'")) ?? 0
            let cs = estimateCacheSize(dir)
            apps.append(AppInfo(bundleId: bid, containerPath: dir, totalSize: totalKb * 1024, cacheSize: cs))
        }
        return apps.sorted { $0.totalSize > $1.totalSize }
    }

    private static func extractBid(from plist: String) -> String? {
        for line in plist.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.contains("MCMMetadataIdentifier") else { continue }
            let parts = t.components(separatedBy: "\"")
            if parts.count >= 4 { return parts[3] }
        }
        return nil
    }

    static func estimateCacheSize(_ container: String) -> Int64 {
        var total: Int64 = 0
        for (rel, _) in safePaths + standardPaths + deepPaths {
            if let k = Int64(sh("du -sk '\(container)/\(rel)' 2>/dev/null | awk '{print $1}'")) { total += k * 1024 }
        }
        return total
    }

    static func duSize(_ path: String) -> Int64 {
        (Int64(sh("du -sk '\(path)' 2>/dev/null | awk '{print $1}'")) ?? 0) * 1024
    }

    static func paths(for level: CleanLevel) -> [(String, String)] {
        switch level {
        case .safe: return safePaths
        case .standard: return safePaths + standardPaths
        case .deep: return safePaths + standardPaths + deepPaths
        }
    }
}
