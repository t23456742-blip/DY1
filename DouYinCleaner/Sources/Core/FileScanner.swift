import Foundation

/// 扫描器 - 用 LSApplicationWorkspace 私有 API
final class FileScanner {
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

    /// 扫描: 通过 LSApplicationWorkspace 获取已安装 App 容器
    static func scanAll() -> [AppInfo] {
        var apps: [AppInfo] = []
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else { return apps }
        guard let ws = cls.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject else { return apps }
        guard let allApps = ws.perform(NSSelectorFromString("allApplications"))?.takeUnretainedValue() as? [NSObject] else { return apps }

        for appProxy in allApps {
            guard let bid = appProxy.perform(NSSelectorFromString("applicationIdentifier"))?.takeUnretainedValue() as? String else { continue }
            guard targetBundleIds.contains(bid) else { continue }

            // 数据容器路径
            var containerPath = "/var/mobile/Containers/Data/Application/" + bid // fallback
            if let urlVal = appProxy.perform(NSSelectorFromString("dataContainerURL"))?.takeUnretainedValue() {
                if let url = urlVal as? URL, url.path.hasPrefix("/") {
                    containerPath = url.path
                }
            }

            let total = FileScanner.sh("du -sk '\(containerPath)' 2>/dev/null | awk '{print $1}'")
            let totalKb = Int64(total) ?? 0
            let cache = estimateCacheSize(containerPath)

            apps.append(AppInfo(bundleId: bid, containerPath: containerPath, totalSize: totalKb * 1024, cacheSize: cache))
        }
        return apps.sorted { $0.totalSize > $1.totalSize }
    }

    static func estimateCacheSize(_ c: String) -> Int64 {
        var t: Int64 = 0
        for (r, _) in safePaths + standardPaths + deepPaths {
            if let k = Int64(sh("du -sk '\(c)/\(r)' 2>/dev/null | awk '{print $1}'")) { t += k * 1024 }
        }
        return t
    }

    static func duSize(_ p: String) -> Int64 {
        (Int64(sh("du -sk '\(p)' 2>/dev/null | awk '{print $1}'")) ?? 0) * 1024
    }

    static func paths(for lvl: CleanLevel) -> [(String, String)] {
        switch lvl {
        case .safe: return safePaths
        case .standard: return safePaths + standardPaths
        case .deep: return safePaths + standardPaths + deepPaths
        }
    }

    // MARK: - posix_spawn shell
    static func sh(_ cmd: String) -> String {
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sh"), strdup("-c"), strdup(cmd), nil]
        defer { for a in argv { free(a) } }
        var pid: pid_t = 0; var fds: [Int32] = [0, 0]; pipe(&fds)
        var act: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&act)
        posix_spawn_file_actions_adddup2(&act, fds[1], STDOUT_FILENO)
        posix_spawn_file_actions_addclose(&act, fds[0])
        let r = posix_spawn(&pid, "/bin/sh", &act, nil, argv, environ)
        posix_spawn_file_actions_destroy(&act); close(fds[1])
        guard r == 0 else { return "" }
        var out = ""; var buf = [CChar](repeating: 0, count: 8192)
        while true { let n = read(fds[0], &buf, buf.count); if n <= 0 { break }; out += String(bytes: Data(bytes: buf, count: n), encoding: .utf8) ?? "" }
        close(fds[0]); var st: Int32 = 0; waitpid(pid, &st, 0)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
