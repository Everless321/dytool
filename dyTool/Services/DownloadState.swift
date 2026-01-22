//
//  DownloadState.swift
//  dyTool
//
//  下载状态管理 - 本地模式
//

import Foundation
import Combine

class DownloadState: ObservableObject {
    static let shared = DownloadState()

    // 下载状态
    @Published var status: DownloadStatus = .idle
    @Published var isDownloading: Bool = false
    @Published var currentUser: Int = 0
    @Published var totalUsers: Int = 0
    @Published var currentUserName: String = ""
    @Published var successCount: Int = 0
    @Published var failCount: Int = 0

    // 日志
    @Published var logs: [LogEntry] = []

    private init() {}

    // MARK: - 下载控制

    func startDownload(users: [DouyinUser]? = nil) {
        let usersToDownload = users ?? DatabaseService.shared.users
        guard !usersToDownload.isEmpty else {
            addLog("没有用户可下载", level: .warning)
            return
        }

        let cookie = DatabaseService.shared.getCookie()
        guard !cookie.isEmpty else {
            addLog("请先设置 Cookie", level: .error)
            status = .error
            return
        }

        let settings = DatabaseService.shared.settings

        logs.removeAll()
        status = .downloading
        isDownloading = true
        successCount = 0
        failCount = 0
        currentUser = 0
        totalUsers = usersToDownload.count

        addLog("开始下载 \(usersToDownload.count) 个用户...", level: .info)
        addLog("保存路径: \(settings.path)", level: .info)
        addLog("Cookie 长度: \(cookie.count) 字符", level: .info)
        if settings.parallel {
            addLog("并发模式: 最大 \(settings.maxWorkers) 个任务", level: .info)
        } else {
            addLog("串行模式", level: .info)
        }

        F2Service.shared.downloadUsers(
            users: usersToDownload,
            cookie: cookie,
            defaultPath: settings.path,
            parallel: settings.parallel,
            maxWorkers: settings.maxWorkers,
            onUserStart: { [weak self] current, total, user in
                self?.currentUser = current
                self?.totalUsers = total
                self?.currentUserName = user.displayName
                self?.addLog("[\(current)/\(total)] 开始下载: \(user.displayName)", level: .info)
            },
            onUserComplete: { [weak self] current, total, user, success, errorMessage in
                if success {
                    self?.successCount += 1
                    self?.addLog("✓ \(user.displayName) 下载完成", level: .success)
                } else {
                    self?.failCount += 1
                    if let errMsg = errorMessage {
                        self?.addLog("✗ \(user.displayName) 下载失败: \(errMsg)", level: .error)
                    } else {
                        self?.addLog("✗ \(user.displayName) 下载失败", level: .error)
                    }
                }
            },
            onProgress: { [weak self] line in
                // 解析 f2 输出日志
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self?.addLog(trimmed, level: .info)
                }
            },
            completion: { [weak self] success, fail in
                if fail > 0 && success == 0 {
                    self?.status = .error
                } else {
                    self?.status = .completed
                }
                self?.isDownloading = false
                self?.addLog("下载完成 - 成功: \(success), 失败: \(fail)", level: .info)
            }
        )
    }

    func stopDownload() {
        F2Service.shared.stopDownload()
        status = .cancelled
        isDownloading = false
        addLog("下载已取消", level: .warning)
    }

    func reset() {
        status = .idle
        isDownloading = false
        currentUser = 0
        totalUsers = 0
        currentUserName = ""
        successCount = 0
        failCount = 0
    }

    // MARK: - 日志

    func addLog(_ message: String, level: LogLevel) {
        let entry = LogEntry(message: message, level: level, timestamp: Date())
        DispatchQueue.main.async {
            self.logs.append(entry)
            if self.logs.count > 500 {
                self.logs.removeFirst(100)
            }
        }
    }
}

// MARK: - 日志模型

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let level: LogLevel
    let timestamp: Date

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

enum LogLevel {
    case info
    case success
    case warning
    case error

    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
}
