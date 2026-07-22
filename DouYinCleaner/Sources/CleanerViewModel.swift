import SwiftUI
import Combine

/// 界面状态
enum AppState {
    case idle, scanning, ready, cleaning, done, error(String)
}

/// 主 ViewModel
@MainActor
final class CleanerViewModel: ObservableObject {
    @Published var state: AppState = .idle
    @Published var apps: [AppInfo] = []
    @Published var selectedLevel: CleanLevel = .deep
    @Published var result: CleanResult?
    @Published var cleanedCount = 0
    @Published var totalCleanCount = 0

    private let scanner = FileScanner.self
    private let engine = CleanerEngine()

    var totalSize: Int64 { apps.reduce(0) { $0 + $1.totalSize } }
    var totalCacheSize: Int64 { apps.reduce(0) { $0 + $1.cacheSize } }

    func scan() async {
        state = .scanning
        apps = []

        await Task.detached(priority: .userInitiated) { [self] in
            await MainActor.run { self.state = .scanning }
            let found = FileScanner.scanAll()
            await MainActor.run {
                self.apps = found
                self.state = found.isEmpty ? .error("未检测到抖音应用, 请确认已安装抖音/TikTok") : .ready
            }
        }.value
    }

    func clean() async {
        let selected = apps.filter(\.isSelected)
        guard !selected.isEmpty else { return }

        state = .cleaning
        cleanedCount = 0
        totalCleanCount = selected.count

        await Task.detached(priority: .userInitiated) { [self] in
            let engine = CleanerEngine()
            var allCleaned: [CleanPathDetail] = []
            var allErrors: [String] = []
            var beforeSum: Int64 = 0
            var afterSum: Int64 = 0

            for app in selected {
                let r = engine.clean(app: app, level: self.selectedLevel)
                allCleaned.append(contentsOf: r.cleanedPaths)
                allErrors.append(contentsOf: r.errors)
                beforeSum += r.beforeBytes
                afterSum += r.afterBytes
                await MainActor.run { self.cleanedCount += 1 }
            }

            let freed = max(0, beforeSum - afterSum)
            let result = CleanResult(
                freedBytes: freed,
                beforeBytes: beforeSum,
                afterBytes: afterSum,
                cleanedPaths: allCleaned,
                errors: allErrors
            )

            await MainActor.run {
                self.result = result
                self.state = .done
            }
        }.value
    }
}
