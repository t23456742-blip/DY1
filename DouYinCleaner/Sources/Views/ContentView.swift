import SwiftUI

/// 主界面
struct ContentView: View {
    @StateObject private var vm = CleanerViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch vm.state {
                case .idle:
                    idleView
                case .scanning:
                    scanningView
                case .ready:
                    readyView
                case .cleaning:
                    cleaningView
                case .done:
                    doneView
                case .error(let msg):
                    errorView(msg)
                }
            }
            .navigationTitle("抖音清理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if case .ready = vm.state {
                        Button("刷新") { Task { await vm.scan() } }
                    }
                }
            }
        }
    }

    // MARK: - 初始界面
    private var idleView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "broom")
                .font(.system(size: 60))
                .foregroundColor(.cyan)
            Text("抖音缓存清理")
                .font(.title2).bold()
            Text("专治备份包太大, 一键瘦身到原来的 10%")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: { Task { await vm.scan() } }) {
                Label("扫描抖音缓存", systemImage: "magnifyingglass")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.cyan)
            Spacer()
        }
    }

    // MARK: - 扫描中
    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("正在扫描抖音数据...")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - 扫描完成
    private var readyView: some View {
        VStack(spacing: 0) {
            // 摘要卡片
            summaryCard
                .padding(.horizontal)
                .padding(.top, 8)

            // App 列表
            List {
                Section("检测到的抖音实例 (\(vm.apps.count))") {
                    ForEach(vm.apps.indices, id: \.self) { i in
                        appRow(vm.apps[i], index: i)
                    }
                }

                Section("清理级别") {
                    ForEach(CleanLevel.allCases) { level in
                        levelRow(level)
                    }
                }
            }

            // 清理按钮
            Button(action: { Task { await vm.clean() } }) {
                Label("开始清理 (\(vm.selectedLevel.rawValue))", systemImage: "burst")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.cyan)
            .padding()
            .disabled(vm.apps.filter(\.isSelected).isEmpty)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("总占用").font(.caption).foregroundColor(.secondary)
                    Text(formatBytes(vm.totalSize)).font(.title2).bold()
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("可清理").font(.caption).foregroundColor(.secondary)
                    Text(formatBytes(vm.totalCacheSize))
                        .font(.title2).bold()
                        .foregroundColor(.cyan)
                }
            }
            ProgressView(value: vm.totalSize > 0 ? Double(vm.totalCacheSize) / Double(vm.totalSize) : 0)
                .tint(.cyan)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func appRow(_ app: AppInfo, index: Int) -> some View {
        HStack {
            Toggle(isOn: $vm.apps[index].isSelected) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.displayName).font(.headline)
                    Text(app.bundleId).font(.caption).foregroundColor(.secondary)
                    Text("数据: \(app.totalSizeFormatted)  |  可清理: \(app.cacheSizeFormatted)")
                        .font(.caption)
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func levelRow(_ level: CleanLevel) -> some View {
        Button {
            vm.selectedLevel = level
        } label: {
            HStack(spacing: 12) {
                Text(level.icon).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.rawValue).font(.headline)
                    Text(level.description).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if vm.selectedLevel == level {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cyan)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 清理中
    private var cleaningView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("正在清理...")
                .font(.headline)
            Text("\(vm.cleanedCount) / \(vm.totalCleanCount) 项")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - 完成
    private var doneView: some View {
        VStack(spacing: 0) {
            // 结果卡片
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("清理完成")
                    .font(.title2).bold()
                Text("已瘦身 \(vm.result?.savedPercent ?? 0)%")
                    .font(.headline)
                    .foregroundColor(.cyan)

                Divider()

                HStack {
                    statItem("清理前", vm.result?.beforeFormatted ?? "-")
                    Spacer()
                    statItem("清理后", vm.result?.afterFormatted ?? "-")
                    Spacer()
                    statItem("释放", vm.result?.freedFormatted ?? "-")
                }

                if !(vm.result?.cleanedPaths.isEmpty ?? true) {
                    Divider()
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(vm.result?.cleanedPaths ?? []) { detail in
                                HStack {
                                    Image(systemName: detail.success ? "checkmark.circle" : "xmark.circle")
                                        .foregroundColor(detail.success ? .green : .red)
                                    Text(detail.description)
                                        .font(.caption)
                                    Spacer()
                                    Text(formatBytes(detail.bytesFreed))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .padding()

            Spacer()

            VStack(spacing: 8) {
                Button {
                    Task { await vm.scan() }
                } label: {
                    Label("再来一次", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.cyan)

                Button("用 AppData 备份") {
                    // 尝试打开 AppData
                    if let url = URL(string: "appdatabackup://") {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    // MARK: - 错误
    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("出错了")
                .font(.title2).bold()
            Text(msg)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("重试") { Task { await vm.scan() } }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.subheadline).bold()
        }
    }
}
