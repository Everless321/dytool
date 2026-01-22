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
        }
        .onChange(of: databaseService.users) { _, newUsers in
            let currentIds = Set(newUsers.map { $0.id })
            selectedUserIds = selectedUserIds.intersection(currentIds)
            if selectedUserIds.isEmpty {
                selectedUserIds = currentIds
            }
        }
    }

    // 计算选中的用户
    private var selectedUsers: [DouyinUser] {
        databaseService.users.filter { selectedUserIds.contains($0.id) }
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

                Text("\(selectedUsers.count) / \(databaseService.users.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    if selectedUserIds.count == databaseService.users.count {
                        selectedUserIds.removeAll()
                    } else {
                        selectedUserIds = Set(databaseService.users.map { $0.id })
                    }
                } label: {
                    Text(selectedUserIds.count == databaseService.users.count ? "取消全选" : "全选")
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if showUserSelection {
                Divider()
                userList
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var userList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(databaseService.users) { user in
                    userRow(user: user)
                }
            }
        }
        .frame(maxHeight: 200)
    }

    private func userRow(user: DouyinUser) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selectedUserIds.contains(user.id) ? "checkmark.circle.fill" : "circle")
                .foregroundColor(selectedUserIds.contains(user.id) ? .accentColor : .secondary)

            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay {
                    Text(String(user.displayName.prefix(1)))
                        .font(.caption)
                        .foregroundColor(.blue)
                }

            Text(user.displayName)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            Text(user.maxCounts == 0 ? "不限" : "\(user.maxCounts)个")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedUserIds.contains(user.id) {
                selectedUserIds.remove(user.id)
            } else {
                selectedUserIds.insert(user.id)
            }
        }
        .background(selectedUserIds.contains(user.id) ? Color.accentColor.opacity(0.1) : Color.clear)
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

#Preview {
    DownloadView()
        .environmentObject(DatabaseService.shared)
        .environmentObject(F2Service.shared)
        .environmentObject(DownloadState.shared)
}
