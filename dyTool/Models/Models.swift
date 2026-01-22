//
//  Models.swift
//  dyTool
//
//  数据模型定义
//

import Foundation

// MARK: - 通用响应

struct APIResponse: Codable {
    let message: String?
    let detail: String?
}

// MARK: - 用户模型

struct DouyinUser: Identifiable, Codable, Equatable {
    let id: String
    let url: String
    var mode: String
    var maxCounts: Int
    var interval: String?
    var nickname: String?

    enum CodingKeys: String, CodingKey {
        case id, url, mode, interval, nickname
        case maxCounts = "max_counts"
    }

    var displayName: String {
        nickname ?? extractUsername()
    }

    private func extractUsername() -> String {
        if let match = url.range(of: #"user/([^/?]+)"#, options: .regularExpression) {
            let id = String(url[match]).replacingOccurrences(of: "user/", with: "")
            return String(id.prefix(15))
        }
        return String(url.suffix(20))
    }
}

// MARK: - 下载状态

enum DownloadStatus: String, Codable {
    case idle
    case downloading
    case embedding
    case completed
    case error
    case cancelled
}

struct DownloadStatusResponse: Codable {
    let status: String
    let currentUser: Int
    let totalUsers: Int
    let currentUserName: String
    let successCount: Int
    let failCount: Int

    enum CodingKeys: String, CodingKey {
        case status
        case currentUser = "current_user"
        case totalUsers = "total_users"
        case currentUserName = "current_user_name"
        case successCount = "success_count"
        case failCount = "fail_count"
    }
}

// MARK: - 视频模型

struct Video: Identifiable, Codable {
    let id: String
    let filename: String
    let path: String
    let coverPath: String?
    let userFolder: String
    let size: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, filename, path, size
        case coverPath = "cover_path"
        case userFolder = "user_folder"
        case createdAt = "created_at"
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

struct VideoListResponse: Codable {
    let videos: [Video]
    let total: Int
    let page: Int
    let pageSize: Int

    enum CodingKeys: String, CodingKey {
        case videos, total, page
        case pageSize = "page_size"
    }
}

struct UserFolder: Identifiable, Codable {
    let name: String
    let videoCount: Int
    let path: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, path
        case videoCount = "video_count"
    }
}

// MARK: - 设置模型

struct AppSettings: Codable {
    var parallel: Bool
    var maxWorkers: Int
    var onError: String
    var mode: String
    var maxCounts: Int
    var path: String
    var cover: Bool
    var embedCover: Bool

    enum CodingKeys: String, CodingKey {
        case parallel, mode, path, cover
        case maxWorkers = "max_workers"
        case onError = "on_error"
        case maxCounts = "max_counts"
        case embedCover = "embed_cover"
    }

    static var `default`: AppSettings {
        // 默认下载路径使用应用数据目录
        let defaultPath: String = {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("dyTool/Downloads").path
        }()

        return AppSettings(
            parallel: true,
            maxWorkers: 3,
            onError: "skip",
            mode: "post",
            maxCounts: 10,
            path: defaultPath,
            cover: true,
            embedCover: true
        )
    }
}

// MARK: - Cookie 状态

struct CookieStatus: Codable {
    let exists: Bool
    let length: Int
    let preview: String
}

// MARK: - WebSocket 消息

struct WSMessage: Codable {
    let type: String
    let message: String?
    let current: Int?
    let total: Int?
    let user: String?
    let status: String?
    let success: Bool?
    let successCount: Int?
    let failCount: Int?

    enum CodingKeys: String, CodingKey {
        case type, message, current, total, user, status, success
        case successCount = "success_count"
        case failCount = "fail_count"
    }
}

// MARK: - 下载模式

struct DownloadMode: Identifiable {
    let id: String
    let label: String
    let description: String

    static let allModes: [DownloadMode] = [
        DownloadMode(id: "post", label: "主页作品", description: "用户发布的作品"),
        DownloadMode(id: "like", label: "点赞作品", description: "用户点赞的作品"),
        DownloadMode(id: "collection", label: "收藏作品", description: "用户收藏的作品"),
        DownloadMode(id: "collects", label: "收藏夹", description: "收藏夹内的作品"),
        DownloadMode(id: "mix", label: "合集", description: "合集内的作品"),
        DownloadMode(id: "music", label: "收藏音乐", description: "用户收藏的音乐"),
    ]
}
