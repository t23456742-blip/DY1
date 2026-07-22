import Foundation

final class FileScanner {
    static let containerBase = "/var/mobile/Containers/Data/Application"
    static let targetBundleIds = [
        "com.ss.iphone.ugc.Aweme", "com.ss.iphone.ugc.Live",
        "com.ss.iphone.ugc.Lite", "com.zhiliaoapp.musically",
    ]
    static let safePaths: [(String, String)] = [
        ("Library/Caches", "应用缓存"), ("tmp", "临时文件"),
        ("Library/SplashBoard", "启动图快照"), ("Library/Caches/Snapshots", "多任务快照"),
    ]
    static let standardPaths: [(String, String)] = [
        ("Library/WebKit", "WebView 缓存"), ("Library/Cookies", "过期 Cookie"),
        ("Documents/aweme_stat", "统计数据"), ("Documents/aweme_log", "日志文件"),
        ("Documents/BDHLog", "下载日志"), ("Documents/offline_pkg", "离线包缓存"),
    ]
    static let deepPaths: [(String, String)] = [
        ("Documents/aweme_video_cache", "视频预加载"), ("Documents/persistence/video", "视频持久化"),
    ]

    static func scanAll() -> [AppInfo] {
        // 方式1: LSApplicationWorkspace (iOS 16+)
        if let apps = scanViaWorkspace(), !apps.isEmpty { return apps }
        // 方式2: posix_spawn ls
        if let apps = scanViaPosix(), !apps.isEmpty { return apps }
        return []
    }

    private static func scanViaWorkspace() -> [AppInfo]? {
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else { return nil }
        guard let ws = cls.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject else { return nil }
        // iOS 16 用的是 allInstalledApplications
        let selName = responds(ws, "allInstalledApplications") ? "allInstalledApplications" : "allApplications"
        guard let list = ws.perform(NSSelectorFromString(selName))?.takeUnretainedValue() as? [NSObject] else { return nil }

        var apps: [AppInfo] = []
        for proxy in list {
            guard let bid = proxy.perform(NSSelectorFromString("applicationIdentifier"))?.takeUnretainedValue() as? String else { continue }
            guard targetBundleIds.contains(bid) else { continue }
            var path = ""
            if responds(proxy, "dataContainerURL"),
               let u = proxy.perform(NSSelectorFromString("dataContainerURL"))?.takeUnretainedValue() as? URL {
                path = u.path
            } else if responds(proxy, "containerURL"),
                      let u = proxy.perform(NSSelectorFromString("containerURL"))?.takeUnretainedValue() as? URL {
                path = u.path
            }
            guard !path.isEmpty else { continue }
            let kb = Int64(sh("du -sk '\(path)' 2>/dev/null | awk '{print $1}'")) ?? 0
            let cs = estimateCacheSize(path)
            apps.append(AppInfo(bundleId: bid, containerPath: path, totalSize: kb * 1024, cacheSize: cs))
        }
        return apps.sorted { $0.totalSize > $1.totalSize }
    }

    private static func scanViaPosix() -> [AppInfo]? {
        let output = sh("ls '\(containerBase)' 2>/dev/null")
        guard !output.isEmpty else { return nil }
        var apps: [AppInfo] = []
        for uuid in output.components(separatedBy: .newlines) where uuid.count > 30 {
            let dir = "\(containerBase)/\(uuid)"
            guard sh("test -d '\(dir)' && echo 1") == "1" else { continue }
            let meta = "\(dir)/.com.apple.mobile_container_manager.metadata.plist"
            let plist = sh("plutil -p '\(meta)' 2>/dev/null; test -f '\(meta)' && plutil -p '\(meta)' || echo ''")
            guard plist.contains("MCMMetadataIdentifier") else { continue }
            guard let bid = extractBid(plist), targetBundleIds.contains(bid) else { continue }
            let kb = Int64(sh("du -sk '\(dir)' 2>/dev/null | awk '{print $1}'")) ?? 0
            let cs = estimateCacheSize(dir)
            apps.append(AppInfo(bundleId: bid, containerPath: dir, totalSize: kb * 1024, cacheSize: cs))
        }
        return apps.isEmpty ? nil : apps.sorted { $0.totalSize > $1.totalSize }
    }

    private static func extractBid(_ plist: String) -> String? {
        for line in plist.components(separatedBy: .newlines) {
            guard line.contains("MCMMetadataIdentifier") else { continue }
            let p = line.components(separatedBy: "\""); if p.count >= 4 { return p[3] }
        }
        return nil
    }

    private static func responds(_ obj: NSObject, _ sel: String) -> Bool {
        obj.responds(to: NSSelectorFromString(sel))
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
