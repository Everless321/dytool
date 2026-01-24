//
//  UserListView.swift
//  dyTool
//
//  用户管理视图
//

import SwiftUI

struct UserListView: View {
    @EnvironmentObject var databaseService: DatabaseService
    @State private var showAddSheet = false
    @State private var showEditSheet = false
    @State private var showBatchEditSheet = false
    @State private var selectedUser: DouyinUser?
    @State private var errorMessage: String?

    // 批量选择
    @State private var isEditMode = false
    @State private var selectedUsers: Set<String> = []

    // 下载数量缓存
    @State private var downloadCounts: [String: Int] = [:]

    // 刷新用户信息状态
    @State private var refreshingUsers: Set<String> = []
    @State private var isRefreshingAll = false
    @State private var refreshProgress: (current: Int, total: Int) = (0, 0)
    @State private var refreshingUserName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("用户列表")
                    .font(.headline)

                if !databaseService.users.isEmpty {
                    Text("(\(databaseService.users.count))")
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 批量编辑模式按钮
                if !databaseService.users.isEmpty {
                    Button {
                        isEditMode.toggle()
                        if !isEditMode {
                            selectedUsers.removeAll()
                        }
                    } label: {
                        Text(isEditMode ? "完成" : "选择")
                    }
                }

                // 批量操作按钮（选中时显示）
                if isEditMode && !selectedUsers.isEmpty {
                    Button {
                        showBatchEditSheet = true
                    } label: {
                        Label("批量设置 (\(selectedUsers.count))", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // 刷新所有用户信息
                if !databaseService.users.isEmpty {
                    if isRefreshingAll {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text("\(refreshProgress.current)/\(refreshProgress.total)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(refreshingUserName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 80)
                        }
                    } else {
                        Button {
                            refreshAllUserInfo()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("刷新用户信息和下载统计")
                    }
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("添加用户", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            // 批量选择工具栏
            if isEditMode {
                HStack {
                    Button {
                        if selectedUsers.count == databaseService.users.count {
                            selectedUsers.removeAll()
                        } else {
                            selectedUsers = Set(databaseService.users.map { $0.id })
                        }
                    } label: {
                        Text(selectedUsers.count == databaseService.users.count ? "取消全选" : "全选")
                    }

                    Spacer()

                    Text("已选择 \(selectedUsers.count) 个用户")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            }

            // 用户列表
            if databaseService.users.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("暂无用户")
                        .font(.headline)
                    Text("点击上方添加按钮添加抖音用户")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(databaseService.users) { user in
                        HStack {
                            // 多选复选框
                            if isEditMode {
                                Image(systemName: selectedUsers.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedUsers.contains(user.id) ? .accentColor : .secondary)
                                    .onTapGesture {
                                        if selectedUsers.contains(user.id) {
                                            selectedUsers.remove(user.id)
                                        } else {
                                            selectedUsers.insert(user.id)
                                        }
                                    }
                            }

                            UserRowView(
                                user: user,
                                downloadedCount: downloadCounts[user.id] ?? 0,
                                isRefreshing: refreshingUsers.contains(user.id)
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isEditMode {
                                if selectedUsers.contains(user.id) {
                                    selectedUsers.remove(user.id)
                                } else {
                                    selectedUsers.insert(user.id)
                                }
                            }
                        }
                        .contextMenu {
                            Button {
                                DownloadState.shared.startDownload(users: [user])
                            } label: {
                                Label("开始下载", systemImage: "arrow.down.circle")
                            }
                            .disabled(DownloadState.shared.isDownloading)

                            Button {
                                refreshUserInfo(user)
                            } label: {
                                Label("刷新信息", systemImage: "arrow.clockwise")
                            }

                            Button("编辑") {
                                selectedUser = user
                                showEditSheet = true
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                deleteUser(user)
                            }
                        }
                        .onTapGesture(count: 2) {
                            if !isEditMode {
                                selectedUser = user
                                showEditSheet = true
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            // 错误提示
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                }
                .foregroundColor(.red)
                .padding()
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddUserSheet(onAdd: { url, mode, maxCounts, nickname in
                addUser(url: url, mode: mode, maxCounts: maxCounts, nickname: nickname)
            })
        }
        .sheet(item: $selectedUser) { user in
            EditUserSheet(user: user, onSave: { mode, maxCounts, interval, nickname in
                updateUser(user, mode: mode, maxCounts: maxCounts, interval: interval, nickname: nickname)
            })
        }
        .sheet(isPresented: $showBatchEditSheet) {
            BatchEditSheet(
                selectedCount: selectedUsers.count,
                onSave: { maxCounts in
                    batchUpdateMaxCounts(maxCounts)
                }
            )
        }
        .onAppear {
            refreshDownloadCounts()
        }
        .onChange(of: databaseService.users) { _, _ in
            refreshDownloadCounts()
        }
    }

    private func refreshDownloadCounts() {
        downloadCounts = databaseService.getAllDownloadedCounts()
    }

    private func refreshUserInfo(_ user: DouyinUser) {
        guard !refreshingUsers.contains(user.id) else { return }

        refreshingUsers.insert(user.id)
        let cookie = databaseService.getCookie()

        Task {
            do {
                let profile = try await BackendService.shared.parseUser(url: user.url, cookie: cookie)

                await MainActor.run {
                    var updated = user
                    var hasChanges = false

                    if let nickname = profile.nickname, !nickname.isEmpty, nickname != user.nickname {
                        updated.nickname = nickname
                        hasChanges = true
                    }
                    if let awemeCount = profile.awemeCount {
                        updated.awemeCount = awemeCount
                        hasChanges = true
                    }

                    if hasChanges {
                        _ = databaseService.updateUser(updated)
                    }
                    refreshingUsers.remove(user.id)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "刷新失败: \(error.localizedDescription)"
                    refreshingUsers.remove(user.id)
                }
            }
        }
    }

    private func refreshAllUserInfo() {
        guard !isRefreshingAll else { return }

        isRefreshingAll = true
        let cookie = databaseService.getCookie()
        let users = databaseService.users
        refreshProgress = (0, users.count)

        Task {
            var updatedCount = 0

            for (index, user) in users.enumerated() {
                await MainActor.run {
                    refreshProgress = (index + 1, users.count)
                    refreshingUserName = user.displayName
                }

                do {
                    let profile = try await BackendService.shared.parseUser(url: user.url, cookie: cookie)

                    await MainActor.run {
                        var updated = user
                        var hasChanges = false

                        if let nickname = profile.nickname, !nickname.isEmpty, nickname != user.nickname {
                            updated.nickname = nickname
                            hasChanges = true
                        }
                        if let awemeCount = profile.awemeCount {
                            updated.awemeCount = awemeCount
                            hasChanges = true
                        }

                        if hasChanges {
                            _ = databaseService.updateUser(updated)
                            updatedCount += 1
                        }
                    }

                    // 避免请求过快
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                } catch {
                    // 单个用户失败不中断整体刷新
                    continue
                }
            }

            await MainActor.run {
                isRefreshingAll = false
                refreshingUserName = ""
                refreshDownloadCounts()
                if updatedCount > 0 {
                    errorMessage = nil
                }
            }
        }
    }

    private func addUser(url: String, mode: String, maxCounts: Int, nickname: String?) {
        if let _ = databaseService.addUser(url: url, mode: mode, maxCounts: maxCounts, nickname: nickname) {
            showAddSheet = false
            errorMessage = nil
        } else {
            errorMessage = "添加用户失败，可能已存在"
        }
    }

    private func updateUser(_ user: DouyinUser, mode: String, maxCounts: Int, interval: String?, nickname: String?) {
        var updated = user
        updated.mode = mode
        updated.maxCounts = maxCounts
        updated.interval = interval
        updated.nickname = nickname

        if databaseService.updateUser(updated) {
            selectedUser = nil
            errorMessage = nil
        } else {
            errorMessage = "更新用户失败"
        }
    }

    private func deleteUser(_ user: DouyinUser) {
        if databaseService.deleteUser(id: user.id) {
            errorMessage = nil
            selectedUsers.remove(user.id)
        } else {
            errorMessage = "删除用户失败"
        }
    }

    private func batchUpdateMaxCounts(_ maxCounts: Int) {
        var successCount = 0
        for userId in selectedUsers {
            if let user = databaseService.users.first(where: { $0.id == userId }) {
                var updated = user
                updated.maxCounts = maxCounts
                if databaseService.updateUser(updated) {
                    successCount += 1
                }
            }
        }

        if successCount > 0 {
            selectedUsers.removeAll()
            isEditMode = false
            errorMessage = nil
        } else {
            errorMessage = "批量更新失败"
        }
    }
}

// MARK: - 用户行视图

struct UserRowView: View {
    let user: DouyinUser
    let downloadedCount: Int
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 头像占位
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(String(user.displayName.prefix(1)))
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(modeLabel(user.mode), systemImage: modeIcon(user.mode))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if user.maxCounts > 0 {
                        Text("最多 \(user.maxCounts) 个")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // 显示下载进度：已下载/总数
                    if let total = user.awemeCount, total > 0 {
                        Text("\(downloadedCount)/\(total)")
                            .font(.caption)
                            .foregroundColor(downloadedCount >= total ? .green : .orange)
                    } else if downloadedCount > 0 {
                        Text("\(downloadedCount) 已下载")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case "post": return "主页"
        case "like": return "点赞"
        case "collection": return "收藏"
        case "collects": return "收藏夹"
        case "mix": return "合集"
        case "music": return "音乐"
        default: return mode
        }
    }

    private func modeIcon(_ mode: String) -> String {
        switch mode {
        case "post": return "house"
        case "like": return "heart"
        case "collection": return "star"
        case "collects": return "folder"
        case "mix": return "rectangle.stack"
        case "music": return "music.note"
        default: return "questionmark"
        }
    }
}

// MARK: - 添加用户表单

struct AddUserSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var db: DatabaseService
    @State private var url = ""
    @State private var mode = "post"
    @State private var maxCounts = 0
    @State private var nickname = ""

    // 用户信息获取状态
    @State private var isFetching = false
    @State private var fetchedProfile: ParsedUserProfile?
    @State private var fetchError: String?

    let onAdd: (String, String, Int, String?) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("添加用户")
                .font(.headline)

            Form {
                // URL 输入区域
                HStack {
                    TextField("抖音用户链接", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: url) { _, newValue in
                            // URL 变化时重置状态
                            if fetchedProfile != nil && !newValue.isEmpty {
                                fetchedProfile = nil
                                fetchError = nil
                            }
                        }
                        .onSubmit {
                            fetchUserInfo()
                        }

                    if isFetching {
                        ProgressView()
                            .controlSize(.small)
                    } else if !url.isEmpty {
                        Button {
                            fetchUserInfo()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("获取用户信息")
                    }
                }

                // 用户信息预览
                if let profile = fetchedProfile {
                    HStack(spacing: 12) {
                        // 头像
                        if let avatarUrl = profile.avatar, let url = URL(string: avatarUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 48, height: 48)
                                .overlay {
                                    Text(String((profile.nickname ?? "U").prefix(1)))
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.nickname ?? "未知用户")
                                .font(.headline)

                            HStack(spacing: 16) {
                                if let count = profile.awemeCount {
                                    Label("\(count) 作品", systemImage: "video")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let count = profile.followerCount {
                                    Label("\(formatCount(count)) 粉丝", systemImage: "person.2")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 8)
                }

                // 错误提示
                if let error = fetchError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                TextField("用户名称 (可选)", text: $nickname)
                    .textFieldStyle(.roundedBorder)

                Picker("下载模式", selection: $mode) {
                    ForEach(DownloadMode.allModes) { m in
                        Text(m.label).tag(m.id)
                    }
                }

                Stepper("最大数量: \(maxCounts == 0 ? "不限" : "\(maxCounts)")", value: $maxCounts, in: 0...1000, step: 10)
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("添加") {
                    onAdd(url, mode, maxCounts, nickname.isEmpty ? nil : nickname)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url.isEmpty || isFetching)
            }
        }
        .padding()
        .frame(width: 450)
        .onAppear {
            extractDouyinUrlFromPasteboard()
        }
    }

    private func fetchUserInfo() {
        guard !url.isEmpty else { return }
        guard isValidDouyinUrl(url) else {
            fetchError = "请输入有效的抖音用户链接"
            return
        }

        isFetching = true
        fetchError = nil

        let cookie = db.getCookie()

        Task {
            do {
                let profile = try await BackendService.shared.parseUser(url: url, cookie: cookie)

                await MainActor.run {
                    fetchedProfile = profile

                    // 检查是否有警告消息（如缺少 Cookie）
                    if let warning = BackendService.shared.lastError {
                        fetchError = warning
                        BackendService.shared.lastError = nil
                    }

                    // 使用后端返回的用户主页 URL（处理作品链接转换）
                    if let homeUrl = profile.homeUrl, !homeUrl.isEmpty {
                        url = homeUrl
                    }

                    // 自动填充昵称
                    if nickname.isEmpty, let name = profile.nickname {
                        nickname = name
                    }
                    isFetching = false
                }
            } catch {
                await MainActor.run {
                    fetchError = error.localizedDescription
                    isFetching = false
                }
            }
        }
    }

    private func isValidDouyinUrl(_ url: String) -> Bool {
        let patterns = [
            #"https://v\.douyin\.com/[A-Za-z0-9_-]+/?"#,  // 短链接
            #"https://www\.douyin\.com/user/[A-Za-z0-9_-]+"#,  // 用户主页
            #"https://www\.douyin\.com/video/[0-9]+"#,  // 视频作品
            #"https://www\.douyin\.com/note/[0-9]+"#,  // 图文作品
        ]

        for pattern in patterns {
            if url.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private func extractDouyinUrlFromPasteboard() {
        guard let pasteboardString = NSPasteboard.general.string(forType: .string) else { return }

        let patterns = [
            #"https://v\.douyin\.com/[A-Za-z0-9_-]+/?"#,  // 短链接（用户主页或作品）
            #"https://www\.douyin\.com/user/[A-Za-z0-9_-]+"#,  // 用户主页
            #"https://www\.douyin\.com/video/[0-9]+"#,  // 视频作品
            #"https://www\.douyin\.com/note/[0-9]+"#,  // 图文作品
        ]

        for pattern in patterns {
            if let range = pasteboardString.range(of: pattern, options: .regularExpression) {
                url = String(pasteboardString[range])
                // 自动获取用户信息
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    fetchUserInfo()
                }
                break
            }
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 10000 {
            return String(format: "%.1f万", Double(count) / 10000)
        }
        return "\(count)"
    }
}

// MARK: - 编辑用户表单

struct EditUserSheet: View {
    @Environment(\.dismiss) var dismiss
    let user: DouyinUser
    @State private var mode: String
    @State private var maxCounts: Int
    @State private var interval: String
    @State private var nickname: String

    let onSave: (String, Int, String?, String?) -> Void

    init(user: DouyinUser, onSave: @escaping (String, Int, String?, String?) -> Void) {
        self.user = user
        self.onSave = onSave
        _mode = State(initialValue: user.mode)
        _maxCounts = State(initialValue: user.maxCounts)
        _interval = State(initialValue: user.interval ?? "")
        _nickname = State(initialValue: user.nickname ?? "")
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("编辑用户")
                .font(.headline)

            Button {
                if let url = URL(string: user.url) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(user.url)
                        .font(.caption)
                        .lineLimit(1)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .help("点击打开链接")

            Form {
                TextField("用户名称", text: $nickname)
                    .textFieldStyle(.roundedBorder)

                Picker("下载模式", selection: $mode) {
                    ForEach(DownloadMode.allModes) { m in
                        Text(m.label).tag(m.id)
                    }
                }

                Stepper("最大数量: \(maxCounts == 0 ? "不限" : "\(maxCounts)")", value: $maxCounts, in: 0...1000, step: 10)

                TextField("时间范围 (可选)", text: $interval)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存") {
                    onSave(mode, maxCounts, interval.isEmpty ? nil : interval, nickname.isEmpty ? nil : nickname)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - 批量编辑表单

struct BatchEditSheet: View {
    @Environment(\.dismiss) var dismiss
    let selectedCount: Int
    @State private var maxCounts: Int = 0

    let onSave: (Int) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("批量设置")
                .font(.headline)

            Text("将为 \(selectedCount) 个用户设置相同的抓取数量")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Form {
                Stepper("最大数量: \(maxCounts == 0 ? "不限" : "\(maxCounts)")", value: $maxCounts, in: 0...1000, step: 10)

                // 快捷按钮
                HStack(spacing: 12) {
                    ForEach([10, 20, 50, 100], id: \.self) { count in
                        Button("\(count)") {
                            maxCounts = count
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("不限") {
                        maxCounts = 0
                    }
                    .buttonStyle(.bordered)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("应用") {
                    onSave(maxCounts)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

#Preview {
    UserListView()
        .environmentObject(DatabaseService.shared)
}
