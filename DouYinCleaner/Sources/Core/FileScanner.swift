import Foundation

/// 扫描器 — 在 /var/mobile/Containers/Data/Application 中查找抖音相关容器
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

    static func scanAll() -> [AppInfo] {
        var apps: [AppInfo] = []
        let fm = FileManager.default
        guard let uuids = try? fm.contentsOfDirectory(atPath: containerBase) else { return apps }
        for uuid in uuids {
            let dirPath = "\(containerBase)/\(uuid)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }
            let metadataPath = "\(dirPath)/.com.apple.mobile_container_manager.metadata.plist"
            guard fm.fileExists(atPath: metadataPath) else { continue }
            guard let bid = extractBundleId(from: metadataPath) else { continue }
            guard targetBundleIds.contains(bid) else { continue }
            let totalSize = directorySize(dirPath)
            let cacheSize = estimateCacheSize(dirPath)
            apps.append(AppInfo(bundleId: bid, containerPath: dirPath, totalSize: totalSize, cacheSize: cacheSize))
        }
        return apps.sorted { $0.totalSize > $1.totalSize }
    }

    private static func extractBundleId(from path: String) -> String? {
        guard let dict = NSDictionary(contentsOfFile: path),
              let id = dict["MCMMetadataIdentifier"] as? String else {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let bid = plist["MCMMetadataIdentifier"] as? String else { return nil }
            return bid
        }
        return id
    }

    static func estimateCacheSize(_ container: String) -> Int64 {
        var total: Int64 = 0
        for (rel, _) in safePaths + standardPaths + deepPaths {
            total += directorySize("\(container)/\(rel)")
        }
        return total
    }

    static func directorySize(_ path: String) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: []
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if values.isDirectory == true { continue }
                if let size = values.fileSize { total += Int64(size) }
            } catch { continue }
        }
        return total
    }

    static func paths(for level: CleanLevel) -> [(String, String)] {
        switch level {
        case .safe:    return safePaths
        case .standard: return safePaths + standardPaths
        case .deep:     return safePaths + standardPaths + deepPaths
        }
    }
}
