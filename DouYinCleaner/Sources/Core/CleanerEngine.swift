import Foundation
import Darwin

/// 清理引擎 — 用 rm -rf，跟扫描器一样走 shell
final class CleanerEngine {

    func clean(app: AppInfo, level: CleanLevel) -> CleanResult {
        let paths = FileScanner.paths(for: level)
        let container = app.containerPath
        let beforeBytes = FileScanner.duSize(container)

        var cleaned: [CleanPathDetail] = []
        var errors: [String] = []

        for (relPath, description) in paths {
            let fullPath = "\(container)/\(relPath)"
            let beforeSize = FileScanner.duSize(fullPath)
            guard beforeSize > 1024 else { continue }

            let result = sh("rm -rf '\(fullPath)' 2>&1")
            if result.isEmpty {
                cleaned.append(CleanPathDetail(path: relPath, description: description, bytesFreed: beforeSize, success: true))
            } else {
                errors.append("删除失败 \(relPath): \(result)")
            }
        }

        // 深度: 删 >10MB 视频
        if level == .deep {
            let findResult = sh("find '\(container)/Documents' -name '*.mp4' -size +10M 2>/dev/null")
            for line in findResult.components(separatedBy: .newlines) where !line.isEmpty {
                let videoPath = line.trimmingCharacters(in: .whitespaces)
                let vs = FileScanner.duSize(videoPath)
                let del = sh("rm -f '\(videoPath)' 2>&1")
                if del.isEmpty {
                    cleaned.append(CleanPathDetail(path: videoPath, description: "大视频缓存", bytesFreed: vs, success: true))
                } else {
                    errors.append("删除视频失败: \(videoPath)")
                }
            }
        }

        let afterBytes = FileScanner.duSize(container)
        let freed = max(0, beforeBytes - afterBytes)

        return CleanResult(
            freedBytes: freed, beforeBytes: beforeBytes, afterBytes: afterBytes,
            cleanedPaths: cleaned, errors: errors
        )
    }

    private func sh(_ cmd: String) -> String {
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
}
