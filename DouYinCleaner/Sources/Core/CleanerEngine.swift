import Foundation

/// 清理引擎
final class CleanerEngine {

    func clean(app: AppInfo, level: CleanLevel) -> CleanResult {
        let paths = FileScanner.paths(for: level)
        let container = app.containerPath
        let beforeBytes = FileScanner.duSize(container)
        var cleaned: [CleanPathDetail] = []
        var errors: [String] = []

        for (relPath, description) in paths {
            let fullPath = "\(container)/\(relPath)"
            let before = FileScanner.duSize(fullPath)
            guard before > 1024 else { continue }
            let err = FileScanner.sh("rm -rf '\(fullPath)' 2>&1")
            if err.isEmpty {
                cleaned.append(CleanPathDetail(path: relPath, description: description, bytesFreed: before, success: true))
            } else {
                errors.append("删除失败 \(relPath): \(err)")
            }
        }

        if level == .deep {
            let found = FileScanner.sh("find '\(container)/Documents' -name '*.mp4' -size +10M 2>/dev/null")
            for line in found.components(separatedBy: .newlines) where !line.isEmpty {
                let vp = line.trimmingCharacters(in: .whitespaces)
                let vs = FileScanner.duSize(vp)
                let del = FileScanner.sh("rm -f '\(vp)' 2>&1")
                if del.isEmpty {
                    cleaned.append(CleanPathDetail(path: vp, description: "大视频缓存", bytesFreed: vs, success: true))
                } else {
                    errors.append("删除视频失败: \(vp)")
                }
            }
        }

        let afterBytes = FileScanner.duSize(container)
        return CleanResult(
            freedBytes: max(0, beforeBytes - afterBytes),
            beforeBytes: beforeBytes, afterBytes: afterBytes,
            cleanedPaths: cleaned, errors: errors
        )
    }
}
