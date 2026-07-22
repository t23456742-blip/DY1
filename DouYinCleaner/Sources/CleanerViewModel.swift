import SwiftUI

/// 界面状态
enum AppState {
    case idle, scanning, ready, cleaning, done, error(String)
}

/// 主 ViewModel - 简化版, 不用 Task.detached
@MainActor
final class CleanerViewModel: ObservableObject {
    @Published var state: AppState = .idle
    @Published var apps: [AppInfo] = []
    @Published var selectedLevel: CleanLevel = .deep
    @Published var result: CleanResult?
    @Published var cleanedCount = 0
    @Published var totalCleanCount = 0

    var totalSize: Int64 { apps.reduce(0) { $0 + $1.totalSize } }
    var totalCacheSize: Int64 { apps.reduce(0) { $0 + $1.cacheSize } }

    func scan() {
        state = .scanning
        apps = []
        let found = FileScanner.scanAll()
        apps = found
        state = found.isEmpty ? .error("未检测到抖音应用, 请确认已安装") : .ready
    }

    func clean() {
        let selected = apps.filter(\.isSelected)
        guard !selected.isEmpty else { return }

        state = .cleaning
        cleanedCount = 0
        totalCleanCount = selected.count

        let engine = CleanerEngine()
        var allCleaned: [CleanPathDetail] = []
        var allErrors: [String] = []
        var beforeSum: Int64 = 0
        var afterSum: Int64 = 0

        for app in selected {
            let r = engine.clean(app: app, level: selectedLevel)
            allCleaned.append(contentsOf: r.cleanedPaths)
            allErrors.append(contentsOf: r.errors)
            beforeSum += r.beforeBytes
            afterSum += r.afterBytes
            cleanedCount += 1
        }

        let freed = max(0, beforeSum - afterSum)
        result = CleanResult(
            freedBytes: freed, beforeBytes: beforeSum, afterBytes: afterSum,
            cleanedPaths: allCleaned, errors: allErrors
        )
        state = .done
    }
}
