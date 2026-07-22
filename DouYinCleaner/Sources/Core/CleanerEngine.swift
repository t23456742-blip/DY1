import Foundation

/// 清理引擎 — 执行实际的目录清理
final class CleanerEngine {

    /// 清理单个 App 容器
    func clean(app: AppInfo, level: CleanLevel) -> CleanResult {
        let paths = FileScanner.paths(for: level)
        let container = app.containerPath
        let beforeBytes = FileScanner.directorySize(container)

        var cleaned: [CleanPathDetail] = []
        var errors: [String] = []

        for (relPath, description) in paths {
            let fullPath = "\(container)/\(relPath)"

            // 通配符路径 (如 Library/Caches/*)
            if relPath.hasSuffix("/*") {
                let basePath = String(relPath.dropLast(2))
                let base = "\(container)/\(basePath)"
                guard fm.fileExists(atPath: base) else { continue }
                do {
                    let items = try fm.contentsOfDirectory(atPath: base)
                    for item in items {
                        let itemPath = "\(base)/\(item)"
                        let size = FileScanner.directorySize(itemPath)
                        if size > 0 {
                            do {
                                try fm.removeItem(atPath: itemPath)
                                cleaned.append(CleanPathDetail(path: itemPath, description: description, bytesFreed: size, success: true))
                            } catch {
                                errors.append("删除失败: \(itemPath) - \(error.localizedDescription)")
                            }
                        }
                    }
                } catch {
                    errors.append("读取目录失败: \(base) - \(error.localizedDescription)")
                }
                continue
            }

            // 精确路径
            guard fm.fileExists(atPath: fullPath) else { continue }
            let size = FileScanner.directorySize(fullPath)
            guard size > 0 else { continue }

            do {
                try fm.removeItem(atPath: fullPath)
                cleaned.append(CleanPathDetail(path: relPath, description: description, bytesFreed: size, success: true))
            } catch {
                // 尝试逐文件删除
                do {
                    let items = try fm.contentsOfDirectory(atPath: fullPath)
                    var subTotal: Int64 = 0
                    for item in items {
                        let ip = "\(fullPath)/\(item)"
                        let sz = FileScanner.directorySize(ip)
                        do { try fm.removeItem(atPath: ip); subTotal += sz }
                        catch { errors.append("删除失败: \(ip)") }
                    }
                    if subTotal > 0 {
                        cleaned.append(CleanPathDetail(path: relPath, description: description, bytesFreed: subTotal, success: true))
                    }
                } catch {
                    errors.append("路径失败: \(relPath) - \(error.localizedDescription)")
                }
            }
        }

        // 深度模式: 删 >10MB 的 mp4
        if level == .deep {
            let docsPath = "\(container)/Documents"
            do {
                let enumerator = fm.enumerator(at: URL(fileURLWithPath: docsPath), includingPropertiesForKeys: [.fileSizeKey], options: [])
                while let fileURL = enumerator?.nextObject() as? URL {
                    guard fileURL.pathExtension.lowercased() == "mp4" else { continue }
                    guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 10_485_760 else { continue }
                    do {
                        try fm.removeItem(at: fileURL)
                        cleaned.append(CleanPathDetail(path: fileURL.path, description: "大视频缓存", bytesFreed: Int64(size), success: true))
                    } catch {
                        errors.append("删除视频失败: \(fileURL.lastPathComponent)")
                    }
                }
            } catch {
                errors.append("深度扫描失败: \(error.localizedDescription)")
            }
        }

        let afterBytes = FileScanner.directorySize(container)
        let freed = max(0, beforeBytes - afterBytes)

        return CleanResult(
            freedBytes: freed,
            beforeBytes: beforeBytes,
            afterBytes: afterBytes,
            cleanedPaths: cleaned,
            errors: errors
        )
    }
}
