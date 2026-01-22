//
//  SettingsView.swift
//  dyTool
//
//  设置视图
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var databaseService: DatabaseService
    @State private var settings = AppSettings.default
    @State private var cookie = ""
    @State private var showCookieSheet = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            // 下载设置
            Section("下载设置") {
                Picker("默认模式", selection: $settings.mode) {
                    ForEach(DownloadMode.allModes) { mode in
                        Text(mode.label).tag(mode.id)
                    }
                }

                Stepper("默认数量: \(settings.maxCounts == 0 ? "不限" : "\(settings.maxCounts)")",
                        value: $settings.maxCounts, in: 0...1000, step: 10)

                TextField("保存路径", text: $settings.path)
            }

            // 并行设置
            Section("并行下载") {
                Toggle("启用并行下载", isOn: $settings.parallel)

                if settings.parallel {
                    Stepper("最大并发数: \(settings.maxWorkers)", value: $settings.maxWorkers, in: 1...10)
                }

                Picker("出错处理", selection: $settings.onError) {
                    Text("跳过").tag("skip")
                    Text("停止").tag("stop")
                }
            }

            // 封面设置
            Section("封面设置") {
                Toggle("下载封面", isOn: $settings.cover)
                Toggle("自动嵌入封面", isOn: $settings.embedCover)
                    .disabled(!settings.cover)
            }

            // Cookie 设置
            Section("Cookie") {
                HStack {
                    Circle()
                        .fill(cookie.isEmpty ? .red : .green)
                        .frame(width: 8, height: 8)
                    Text(cookie.isEmpty ? "未配置" : "已配置")

                    if !cookie.isEmpty {
                        Text("(\(cookie.count) 字符)")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(cookie.isEmpty ? "设置" : "更新") {
                        showCookieSheet = true
                    }
                }

                if !cookie.isEmpty {
                    Text(String(cookie.prefix(50)) + "...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // 消息提示
            if let msg = message {
                Section {
                    HStack {
                        Image(systemName: isError ? "xmark.circle" : "checkmark.circle")
                            .foregroundColor(isError ? .red : .green)
                        Text(msg)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveSettings()
                }
            }
        }
        .onAppear {
            loadSettings()
        }
        .sheet(isPresented: $showCookieSheet) {
            CookieSheet(cookie: $cookie) {
                saveCookie()
            }
        }
    }

    private func loadSettings() {
        settings = databaseService.settings
        cookie = databaseService.getCookie()
    }

    private func saveSettings() {
        databaseService.updateSettings(settings)
        message = "设置已保存"
        isError = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            message = nil
        }
    }

    private func saveCookie() {
        guard !cookie.isEmpty else { return }
        databaseService.setCookie(cookie)
        showCookieSheet = false
        message = "Cookie 已更新"
        isError = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            message = nil
        }
    }
}

// MARK: - Cookie 编辑表单

struct CookieSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var cookie: String
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("设置 Cookie")
                .font(.headline)

            Text("从浏览器复制抖音的 Cookie 值粘贴到下方")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextEditor(text: $cookie)
                .font(.system(.body, design: .monospaced))
                .frame(height: 150)
                .border(Color.gray.opacity(0.3))

            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("从剪贴板粘贴") {
                    if let content = NSPasteboard.general.string(forType: .string) {
                        cookie = content
                    }
                }

                Button("保存") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cookie.isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
    }
}

#Preview {
    SettingsView()
        .environmentObject(DatabaseService.shared)
}
