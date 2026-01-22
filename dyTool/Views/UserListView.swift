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

                            UserRowView(user: user)
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

    var body: some View {
        HStack(spacing: 12) {
            // 头像占位
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(user.displayName.prefix(1)))
                        .font(.headline)
                        .foregroundColor(.blue)
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
    @State private var url = ""
    @State private var mode = "post"
    @State private var maxCounts = 0
    @State private var nickname = ""

    let onAdd: (String, String, Int, String?) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("添加用户")
                .font(.headline)

            Form {
                TextField("抖音用户链接", text: $url)
                    .textFieldStyle(.roundedBorder)

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
                .disabled(url.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            extractDouyinUrlFromPasteboard()
        }
    }

    private func extractDouyinUrlFromPasteboard() {
        guard let pasteboardString = NSPasteboard.general.string(forType: .string) else { return }

        // 匹配抖音链接: https://v.douyin.com/xxx 或 https://www.douyin.com/user/xxx
        let patterns = [
            #"https://v\.douyin\.com/[A-Za-z0-9]+/?"#,
            #"https://www\.douyin\.com/user/[A-Za-z0-9_-]+"#
        ]

        for pattern in patterns {
            if let range = pasteboardString.range(of: pattern, options: .regularExpression) {
                url = String(pasteboardString[range])
                break
            }
        }
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
