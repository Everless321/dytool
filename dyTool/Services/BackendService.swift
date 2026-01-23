//
//  BackendService.swift
//  dyTool
//
//  Python 后端 API 服务 - 统一 HTTP 请求类
//

import Foundation
import Combine

// MARK: - 后端 API 响应模型

struct UserParseRequest: Codable {
    let url: String
    let cookie: String?
}

struct UserParseResponse: Codable {
    let success: Bool
    let message: String
    let data: ParsedUserProfile?
}

struct ParsedUserProfile: Codable {
    let secUserId: String
    let uid: String?
    let nickname: String?
    let signature: String?
    let avatar: String?
    let followingCount: Int?
    let followerCount: Int?
    let awemeCount: Int?
    let favoritingCount: Int?
    let totalFavorited: Int?

    enum CodingKeys: String, CodingKey {
        case secUserId = "sec_user_id"
        case uid
        case nickname
        case signature
        case avatar
        case followingCount = "following_count"
        case followerCount = "follower_count"
        case awemeCount = "aweme_count"
        case favoritingCount = "favoriting_count"
        case totalFavorited = "total_favorited"
    }
}

// MARK: - 后端服务

class BackendService: ObservableObject {
    static let shared = BackendService()

    @Published var isConnected: Bool = false
    @Published var lastError: String?

    private let baseURL: String
    private let session: URLSession

    private init() {
        self.baseURL = "http://localhost:8000"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - 健康检查

    func checkHealth() async -> Bool {
        do {
            let _: [String: String] = try await get(path: "/health")
            await MainActor.run { self.isConnected = true }
            return true
        } catch {
            await MainActor.run {
                self.isConnected = false
                self.lastError = error.localizedDescription
            }
            return false
        }
    }

    // MARK: - 用户解析

    func parseUser(url: String, cookie: String? = nil) async throws -> ParsedUserProfile {
        let request = UserParseRequest(url: url, cookie: cookie)
        let response: UserParseResponse = try await post(path: "/api/users/parse", body: request)

        // 即使 success=false，如果有 data 也返回（可能只有 sec_user_id）
        if let profile = response.data {
            // 如果没有完整信息，在 profile 中保留错误消息供 UI 显示
            if !response.success {
                // 可以通过 lastError 传递消息
                await MainActor.run { self.lastError = response.message }
            }
            return profile
        }

        throw BackendError.apiError(response.message)
    }

    // MARK: - HTTP 方法

    private func get<T: Decodable>(path: String) async throws -> T {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return try await execute(request)
    }

    private func post<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        return try await execute(request)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        // 优先使用 URLSession，如果失败则使用 curl（支持 HTTP）
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendError.invalidResponse
            }

            if httpResponse.statusCode >= 400 {
                if let errorJson = try? JSONDecoder().decode([String: String].self, from: data),
                   let detail = errorJson["detail"] {
                    throw BackendError.apiError(detail)
                }
                throw BackendError.httpError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch let urlError as URLError where urlError.code == .appTransportSecurityRequiresSecureConnection {
            // ATS 阻止了 HTTP 请求，使用 curl 作为后备方案
            return try await executeWithCurl(request)
        }
    }

    private func executeWithCurl<T: Decodable>(_ request: URLRequest) async throws -> T {
        guard let url = request.url else {
            throw BackendError.invalidRequest
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var args = ["-s", "-S", "-L", "-w", "\n%{http_code}"]

                // 添加请求方法
                if let method = request.httpMethod, method != "GET" {
                    args.append(contentsOf: ["-X", method])
                }

                // 添加请求头
                if let headers = request.allHTTPHeaderFields {
                    for (key, value) in headers {
                        args.append(contentsOf: ["-H", "\(key): \(value)"])
                    }
                }

                // 添加请求体
                var tempFile: URL?
                if let body = request.httpBody {
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
                    do {
                        try body.write(to: file)
                        tempFile = file
                        args.append(contentsOf: ["-d", "@\(file.path)"])
                    } catch {
                        continuation.resume(throwing: BackendError.requestFailed(error.localizedDescription))
                        return
                    }
                }

                args.append(url.absoluteString)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                process.arguments = args

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    // 清理临时文件
                    if let file = tempFile {
                        try? FileManager.default.removeItem(at: file)
                    }

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    guard let output = String(data: data, encoding: .utf8) else {
                        continuation.resume(throwing: BackendError.invalidResponse)
                        return
                    }

                    // 分离响应体和状态码
                    let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
                    guard lines.count >= 2 else {
                        continuation.resume(throwing: BackendError.invalidResponse)
                        return
                    }

                    let statusCode = Int(lines.last!) ?? 0
                    let body = lines.dropLast().joined(separator: "\n")

                    if statusCode >= 400 {
                        continuation.resume(throwing: BackendError.httpError(statusCode))
                        return
                    }

                    guard let bodyData = body.data(using: .utf8) else {
                        continuation.resume(throwing: BackendError.invalidResponse)
                        return
                    }

                    let decoder = JSONDecoder()
                    let result = try decoder.decode(T.self, from: bodyData)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: BackendError.requestFailed(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - 错误类型

enum BackendError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case requestFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "无效的请求"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let code):
            return "HTTP 错误: \(code)"
        case .apiError(let message):
            return message
        case .requestFailed(let message):
            return "请求失败: \(message)"
        case .notConnected:
            return "后端服务未连接"
        }
    }
}
