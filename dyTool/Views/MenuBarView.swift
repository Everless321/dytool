//
//  MenuBarView.swift
//  dyTool
//
//  菜单栏视图
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var databaseService: DatabaseService
    @EnvironmentObject var f2Service: F2Service
    @EnvironmentObject var downloadState: DownloadState

    var body: some View {
        VStack(spacing: 0) {
            // 状态区域
            VStack(spacing: 8) {
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("本地模式")
                        .font(.headline)
                    Spacer()
                }

                if downloadState.isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("正在下载")
                                .font(.subheadline)
                            Spacer()
                            Text("\(downloadState.currentUser)/\(downloadState.totalUsers)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        ProgressView(value: Double(downloadState.currentUser), total: Double(max(downloadState.totalUsers, 1)))
                            .progressViewStyle(.linear)

                        if !downloadState.currentUserName.isEmpty {
                            Text(downloadState.currentUserName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding()

            Divider()

            // 操作按钮
            VStack(spacing: 0) {
                Button {
                    openMainWindow()
                } label: {
                    HStack {
                        Image(systemName: "macwindow")
                        Text("打开主窗口")
                        Spacer()
                        Text("⌘O")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                if downloadState.isDownloading {
                    Button {
                        downloadState.stopDownload()
                    } label: {
                        HStack {
                            Image(systemName: "stop.circle")
                            Text("停止下载")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                } else {
                    Button {
                        downloadState.startDownload()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle")
                            Text("开始下载")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .disabled(databaseService.users.isEmpty)
                }

                Divider()

                // 最近日志
                if !downloadState.logs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近日志")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        ForEach(downloadState.logs.suffix(3)) { log in
                            HStack(spacing: 4) {
                                Image(systemName: log.level.icon)
                                    .font(.caption2)
                                Text(log.message)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .foregroundColor(colorForLevel(log.level))
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 8)
                    }

                    Divider()
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text("退出")
                        Spacer()
                        Text("⌘Q")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 280)
    }

    private func openMainWindow() {
        if let window = NSApplication.shared.windows.first(where: { $0.title.isEmpty || $0.contentView is NSHostingView<MainView> }) {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(DatabaseService.shared)
        .environmentObject(F2Service.shared)
        .environmentObject(DownloadState.shared)
}
