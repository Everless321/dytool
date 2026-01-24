//
//  DownloadView.swift
//  dyTool
//
//  下载进度视图
//

import SwiftUI

struct DownloadView: View {
    @EnvironmentObject var databaseService: DatabaseService
    @EnvironmentObject var f2Service: F2Service
    @EnvironmentObject var downloadState: DownloadState

    // 用户选择
    @State private var selectedUserIds: Set<String> = []
    @State private var showUserSelection = true

    // 搜索与筛选
    @State private var searchText = ""
    @State private var filterMode: UserFilterMode = .all
    @State private var sortMode: UserSortMode = .default

    // 下载统计缓存
    @State private var downloadCounts: [String: Int] = [:]

    var body: some View {
        VStack(spacing: 0) {
            statusCard
            Divider()

            // 用户选择面板
            if !downloadState.isDownloading {
                userSelectionPanel
            }

            logSection
        }
        .onAppear {
            selectedUserIds = Set(databaseService.users.map { $0.id })
            refreshDownloadCounts()
        }
        .onChange(of: databaseService.users) { _, newUsers in
            let currentIds = Set(newUsers.map { $0.id })
            selectedUserIds = selectedUserIds.intersection(currentIds)
            if selectedUserIds.isEmpty {
                selectedUserIds = currentIds
            }
            refreshDownloadCounts()
        }
        .onChange(of: downloadState.isDownloading) { _, isDownloading in
            if !isDownloading {
                refreshDownloadCounts()
            }
        }
    }

    private func refreshDownloadCounts() {
        downloadCounts = databaseService.getAllDownloadedCounts()
    }

    // 计算选中的用户
    private var selectedUsers: [DouyinUser] {
        databaseService.users.filter { selectedUserIds.contains($0.id) }
    }

    // 筛选和排序后的用户列表
    private var filteredAndSortedUsers: [DouyinUser] {
        var users = databaseService.users

        // 搜索过滤
        if !searchText.isEmpty {
            users = users.filter { user in
                user.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        // 状态筛选
        switch filterMode {
        case .all:
            break
        case .incomplete:
            users = users.filter { user in
                let downloaded = downloadCounts[user.id] ?? 0
                let total = user.awemeCount ?? 0
                return total == 0 || downloaded < total
            }
        case .completed:
            users = users.filter { user in
                let downloaded = downloadCounts[user.id] ?? 0
                let total = user.awemeCount ?? 0
                return total > 0 && downloaded >= total
            }
        }

        // 排序
        switch sortMode {
        case .default:
            break
        case .progressAsc:
            users.sort { u1, u2 in
                let p1 = userProgress(u1)
                let p2 = userProgress(u2)
                return p1 < p2
            }
        case .progressDesc:
            users.sort { u1, u2 in
                let p1 = userProgress(u1)
                let p2 = userProgress(u2)
                return p1 > p2
            }
        case .countDesc:
            users.sort { ($0.awemeCount ?? 0) > ($1.awemeCount ?? 0) }
        case .countAsc:
            users.sort { ($0.awemeCount ?? 0) < ($1.awemeCount ?? 0) }
        }

        return users
    }

    private func userProgress(_ user: DouyinUser) -> Double {
        let downloaded = downloadCounts[user.id] ?? 0
        let total = user.awemeCount ?? 0
        guard total > 0 else { return 0 }
        return Double(downloaded) / Double(total)
    }

    // MARK: - 状态卡片

    private var statusCard: some View {
        VStack(spacing: 16) {
            statusHeader
            progressSection
            controlButtons
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var statusHeader: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: statusIcon)
                    .font(.system(size: 32))
                    .foregroundColor(statusColor)
                    .symbolEffect(.pulse, isActive: downloadState.isDownloading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(statusText)
                    .font(.title2)
                    .fontWeight(.semibold)

                if downloadState.isDownloading {
                    Text("正在下载: \(downloadState.currentUserName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 16) {
                    StatBadge(label: "成功", value: downloadState.successCount, color: .green)
                    StatBadge(label: "失败", value: downloadState.failCount, color: .red)
                    StatBadge(label: "进度", value: downloadState.currentUser, total: downloadState.totalUsers, color: .blue)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if downloadState.totalUsers > 0 {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(downloadState.currentUser), total: Double(downloadState.totalUsers))
                    .progressViewStyle(.linear)
                    .scaleEffect(y: 2)

                HStack {
                    Text("\(downloadState.currentUser) / \(downloadState.totalUsers) 用户")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(Double(downloadState.currentUser) / Double(max(downloadState.totalUsers, 1)) * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 12) {
            if downloadState.isDownloading {
                Button {
                    downloadState.stopDownload()
                } label: {
                    Label("停止下载", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    downloadState.startDownload(users: selectedUsers)
                } label: {
                    Label("开始下载 (\(selectedUsers.count))", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedUsers.isEmpty)
            }

            Button {
                downloadState.reset()
            } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .disabled(downloadState.isDownloading)
        }
    }

    // MARK: - 用户选择面板

    private var userSelectionPanel: some View {
        VStack(spacing: 0) {
            // 标题栏
            userSelectionHeader

            if showUserSelection {
                Divider()
                // 搜索和筛选工具栏
                userSelectionToolbar
                Divider()
                // 用户列表
                userList
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var userSelectionHeader: some View {
        HStack {
            Button {
                withAnimation {
                    showUserSelection.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: showUserSelection ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("选择下载用户")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // 选中统计
            let visibleSelected = filteredAndSortedUsers.filter { selectedUserIds.contains($0.id) }.count
            Text("\(visibleSelected) 选中 / \(filteredAndSortedUsers.count) 显示 / \(databaseService.users.count) 总计")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var userSelectionToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索用户...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

                // 排序菜单
                Menu {
                    Button("默认顺序") { sortMode = .default }
                        .disabled(sortMode == .default)
                    Divider()
                    Button("进度 ↑ 低到高") { sortMode = .progressAsc }
                    Button("进度 ↓ 高到低") { sortMode = .progressDesc }
                    Divider()
                    Button("作品数 ↑ 少到多") { sortMode = .countAsc }
                    Button("作品数 ↓ 多到少") { sortMode = .countDesc }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortMode.label)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 8) {
                // 筛选按钮组
                ForEach(UserFilterMode.allCases, id: \.self) { mode in
                    Button {
                        filterMode = mode
                    } label: {
                        Text(mode.label)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(filterMode == mode ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                            .foregroundColor(filterMode == mode ? .white : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // 快捷操作
                Menu {
                    Button("全选当前列表") {
                        selectAllVisible()
                    }
                    Button("取消选择当前列表") {
                        deselectAllVisible()
                    }
                    Divider()
                    Button("选择未完成的") {
                        selectIncomplete()
                    }
                    Button("选择已完成的") {
                        selectCompleted()
                    }
                    Divider()
                    Button("全选所有") {
                        selectedUserIds = Set(databaseService.users.map { $0.id })
                    }
                    Button("清空选择") {
                        selectedUserIds.removeAll()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                        Text("快捷选择")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func selectAllVisible() {
        for user in filteredAndSortedUsers {
            selectedUserIds.insert(user.id)
        }
    }

    private func deselectAllVisible() {
        for user in filteredAndSortedUsers {
            selectedUserIds.remove(user.id)
        }
    }

    private func selectIncomplete() {
        selectedUserIds.removeAll()
        for user in databaseService.users {
            let downloaded = downloadCounts[user.id] ?? 0
            let total = user.awemeCount ?? 0
            if total == 0 || downloaded < total {
                selectedUserIds.insert(user.id)
            }
        }
    }

    private func selectCompleted() {
        selectedUserIds.removeAll()
        for user in databaseService.users {
            let downloaded = downloadCounts[user.id] ?? 0
            let total = user.awemeCount ?? 0
            if total > 0 && downloaded >= total {
                selectedUserIds.insert(user.id)
            }
        }
    }

    private var userList: some View {
        Group {
            if filteredAndSortedUsers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "没有符合条件的用户" : "未找到 \"\(searchText)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredAndSortedUsers) { user in
                            userRow(user: user)
                            if user.id != filteredAndSortedUsers.last?.id {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }
                .frame(minHeight: 100, maxHeight: 300)
            }
        }
    }

    private func userRow(user: DouyinUser) -> some View {
        let downloaded = downloadCounts[user.id] ?? 0
        let total = user.awemeCount ?? 0
        let progress = total > 0 ? Double(downloaded) / Double(total) : 0
        let isComplete = total > 0 && downloaded >= total

        return HStack(spacing: 12) {
            // 选择框
            Image(systemName: selectedUserIds.contains(user.id) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundColor(selectedUserIds.contains(user.id) ? .accentColor : .secondary)

            // 头像
            Circle()
                .fill(isComplete ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay {
                    Text(String(user.displayName.prefix(1)))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isComplete ? .green : .blue)
                }

            // 用户信息
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // 下载进度
                    if total > 0 {
                        HStack(spacing: 4) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .frame(width: 60)
                            Text("\(downloaded)/\(total)")
                                .font(.caption2)
                                .foregroundColor(isComplete ? .green : .secondary)
                        }
                    } else if downloaded > 0 {
                        Text("已下载 \(downloaded)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("未下载")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // 下载限制
                    Text(user.maxCounts == 0 ? "不限" : "限\(user.maxCounts)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(3)
                }
            }

            Spacer()

            // 完成状态标记
            if isComplete {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedUserIds.contains(user.id) {
                selectedUserIds.remove(user.id)
            } else {
                selectedUserIds.insert(user.id)
            }
        }
        .background(selectedUserIds.contains(user.id) ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    // MARK: - 日志区域

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("下载日志")
                    .font(.headline)
                Spacer()
                Button {
                    downloadState.logs.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(downloadState.logs.isEmpty)
            }
            .padding(.horizontal)
            .padding(.top)

            if downloadState.logs.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("暂无日志")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(downloadState.logs) { log in
                                LogRowView(log: log)
                                    .id(log.id)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onChange(of: downloadState.logs.count) { _, _ in
                        if let lastLog = downloadState.logs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 状态属性

    private var statusColor: Color {
        switch downloadState.status {
        case .idle: return .secondary
        case .downloading: return .blue
        case .embedding: return .purple
        case .completed: return .green
        case .error: return .red
        case .cancelled: return .orange
        }
    }

    private var statusIcon: String {
        switch downloadState.status {
        case .idle: return "arrow.down.circle"
        case .downloading: return "arrow.down.circle.fill"
        case .embedding: return "photo.badge.checkmark"
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    private var statusText: String {
        switch downloadState.status {
        case .idle: return "等待开始"
        case .downloading: return "正在下载"
        case .embedding: return "嵌入封面"
        case .completed: return "下载完成"
        case .error: return "下载出错"
        case .cancelled: return "已取消"
        }
    }
}

// MARK: - 统计徽章

struct StatBadge: View {
    let label: String
    var value: Int
    var total: Int?
    let color: Color

    init(label: String, value: Int, color: Color) {
        self.label = label
        self.value = value
        self.total = nil
        self.color = color
    }

    init(label: String, value: Int, total: Int, color: Color) {
        self.label = label
        self.value = value
        self.total = total
        self.color = color
    }

    var body: some View {
        VStack(spacing: 2) {
            if let total = total {
                Text("\(value)/\(total)")
                    .font(.headline)
                    .foregroundColor(color)
            } else {
                Text("\(value)")
                    .font(.headline)
                    .foregroundColor(color)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 日志行

struct LogRowView: View {
    let log: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(log.formattedTime)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()

            Image(systemName: log.level.icon)
                .font(.caption)
                .foregroundColor(colorForLevel)

            Text(log.message)
                .font(.caption)
                .foregroundColor(colorForLevel)
        }
        .padding(.vertical, 2)
    }

    private var colorForLevel: Color {
        switch log.level {
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - 用户筛选模式

enum UserFilterMode: CaseIterable {
    case all
    case incomplete
    case completed

    var label: String {
        switch self {
        case .all: return "全部"
        case .incomplete: return "未完成"
        case .completed: return "已完成"
        }
    }
}

// MARK: - 用户排序模式

enum UserSortMode {
    case `default`
    case progressAsc
    case progressDesc
    case countAsc
    case countDesc

    var label: String {
        switch self {
        case .default: return "默认"
        case .progressAsc: return "进度↑"
        case .progressDesc: return "进度↓"
        case .countAsc: return "作品↑"
        case .countDesc: return "作品↓"
        }
    }
}

#Preview {
    DownloadView()
        .environmentObject(DatabaseService.shared)
        .environmentObject(F2Service.shared)
        .environmentObject(DownloadState.shared)
}
